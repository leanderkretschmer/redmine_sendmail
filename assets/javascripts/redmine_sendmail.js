(function () {
  'use strict';

  var SENDMAIL_PREVIEW_FLAG = 'sendmailPreviewApproved';
  var SAVE_LABEL_BACKUP_ATTR = 'data-sendmail-original-label';

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  function findIssueForm() {
    return document.querySelector('form#issue-form') ||
           document.querySelector('form.new_issue') ||
           document.querySelector('form.edit_issue') ||
           (document.querySelector('[data-sendmail-form]')
              ? document.querySelector('[data-sendmail-form]').closest('form')
              : null);
  }

  function findSaveButton(form) {
    if (!form) { return null; }
    return form.querySelector('input[type="submit"][name="commit"]') ||
           form.querySelector('button[type="submit"][name="commit"]') ||
           form.querySelector('input[type="submit"]') ||
           form.querySelector('button[type="submit"]');
  }

  function wireSearch(form) {
    var search = form.querySelector('[data-sendmail-recipient-search]');
    if (!search) { return; }
    var items = form.querySelectorAll('[data-sendmail-recipient-item]');
    search.addEventListener('input', function () {
      var q = search.value.trim().toLowerCase();
      for (var i = 0; i < items.length; i++) {
        var blob = items[i].getAttribute('data-search-blob') || '';
        items[i].style.display = (q === '' || blob.indexOf(q) !== -1) ? '' : 'none';
      }
    });
  }

  function updateSaveButtonLabel(form, hasRecipients) {
    var hostForm = findIssueForm();
    var btn = findSaveButton(hostForm);
    if (!btn) { return; }
    if (!btn.hasAttribute(SAVE_LABEL_BACKUP_ATTR)) {
      btn.setAttribute(SAVE_LABEL_BACKUP_ATTR, btn.value || btn.textContent || '');
    }
    var original = btn.getAttribute(SAVE_LABEL_BACKUP_ATTR);
    var sendLabel = (form.getAttribute('data-sendmail-save-and-send-label') || 'Save & Send');
    if (btn.tagName === 'INPUT') {
      btn.value = hasRecipients ? sendLabel : original;
    } else {
      btn.textContent = hasRecipients ? sendLabel : original;
    }
  }

  function wireAdhoc(form) {
    var addBtn = form.querySelector('[data-sendmail-adhoc-add]');
    var rowsContainer = form.querySelector('[data-sendmail-adhoc-rows]');
    var template = form.querySelector('[data-sendmail-adhoc-template]');
    if (!addBtn || !rowsContainer || !template) { return; }
    var counter = 0;

    function addRow() {
      var html = template.innerHTML.replace(/__IDX__/g, String(counter++));
      var div = document.createElement('div');
      div.innerHTML = html.trim();
      var row = div.firstChild;
      rowsContainer.appendChild(row);
      var rm = row.querySelector('[data-sendmail-adhoc-remove]');
      if (rm) {
        rm.addEventListener('click', function () {
          row.parentNode.removeChild(row);
          updateAfterChange(form);
        });
      }
      var inputs = row.querySelectorAll('input, select');
      for (var i = 0; i < inputs.length; i++) {
        inputs[i].addEventListener('input', function () { updateAfterChange(form); updateCreateContactLink(form, row); });
        inputs[i].addEventListener('change', function () { updateAfterChange(form); updateCreateContactLink(form, row); });
      }
      wireCreateContactLink(form, row);
      updateAfterChange(form);
    }

    addBtn.addEventListener('click', addRow);
  }

  // "Create contact" link on an ad-hoc recipient row: opens the project's
  // new-contact page with name and e-mail pre-filled (redmine_contacts reads
  // contact[...] params in ContactsController#new).
  function createContactUrl(form, row) {
    var block = form.querySelector('[data-sendmail-adhoc]');
    var base = block ? (block.getAttribute('data-sendmail-new-contact-url') || '') : '';
    if (!base) { return ''; }
    var emailEl = row.querySelector('.redmine-sendmail-adhoc-email');
    var nameEl  = row.querySelector('.redmine-sendmail-adhoc-name');
    var email = emailEl ? emailEl.value.trim() : '';
    if (!email) { return ''; }
    var name = nameEl ? nameEl.value.trim() : '';
    var parts = name.split(/\s+/).filter(function (p) { return p.length; });
    var first = parts.length ? parts[0] : email.split('@')[0];
    var last  = parts.length > 1 ? parts.slice(1).join(' ') : '';
    var q = 'contact[first_name]=' + encodeURIComponent(first) +
            '&contact[last_name]=' + encodeURIComponent(last) +
            '&contact[email]=' + encodeURIComponent(email);
    return base + (base.indexOf('?') === -1 ? '?' : '&') + q;
  }

  function updateCreateContactLink(form, row) {
    var link = row.querySelector('[data-sendmail-adhoc-create-contact]');
    if (!link) { return; }
    var url = createContactUrl(form, row);
    link.style.display = url ? '' : 'none';
    if (url) { link.setAttribute('href', url); }
  }

  function wireCreateContactLink(form, row) {
    var link = row.querySelector('[data-sendmail-adhoc-create-contact]');
    if (!link) { return; }
    link.setAttribute('target', '_blank');
    link.setAttribute('rel', 'noopener');
    link.addEventListener('click', function (e) {
      var url = createContactUrl(form, row);
      if (!url) { e.preventDefault(); return; }
      link.setAttribute('href', url);
    });
    updateCreateContactLink(form, row);
  }

  function updateAfterChange(form) {
    var has = hasAnyRecipient(form);
    var subjectRow = form.querySelector('[data-sendmail-subject-row]');
    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var optionsRow = form.querySelector('[data-sendmail-options-row]');
    var hint = form.querySelector('[data-sendmail-hint]');
    if (subjectRow) { subjectRow.style.display = has ? '' : 'none'; }
    if (optionsRow) { optionsRow.style.display = has ? '' : 'none'; }
    if (hint) { hint.style.display = has ? '' : 'none'; }
    if (subjectInput) {
      if (!has) { subjectInput.value = ''; }
    }
    updateSaveButtonLabel(form, has);
    scheduleLivePreview(form);
  }

  // ---- per-mail options (form of address, first name only, quote) --------

  function getOptionState(form) {
    var foaEl = form.querySelector('[data-sendmail-option="form_of_address"]:checked');
    var fnoEl = form.querySelector('[data-sendmail-option="first_name_only"]');
    var quoteEl = form.querySelector('[data-sendmail-option="quote"]');
    var replyEl = form.querySelector('[data-sendmail-reply-journal-id]');
    var replyId = replyEl ? replyEl.value.trim() : '';
    return {
      formOfAddress:  foaEl ? foaEl.value : '',
      firstNameOnly:  !!(fnoEl && fnoEl.checked),
      quote:          !!(quoteEl && quoteEl.checked && replyId),
      replyJournalId: replyId
    };
  }

  function wireOptions(form) {
    var opts = form.querySelectorAll('[data-sendmail-option]');
    for (var i = 0; i < opts.length; i++) {
      opts[i].addEventListener('change', function () { scheduleLivePreview(form); });
    }
    var clear = form.querySelector('[data-sendmail-reply-clear]');
    if (clear) {
      clear.addEventListener('click', function (e) {
        e.preventDefault();
        clearReplyReference(form);
      });
    }
  }

  function setReplyReference(form, journalId, indice, labels) {
    var replyEl = form.querySelector('[data-sendmail-reply-journal-id]');
    var row = form.querySelector('[data-sendmail-quote-row]');
    var target = form.querySelector('[data-sendmail-reply-target]');
    var quoteEl = form.querySelector('[data-sendmail-option="quote"]');
    if (replyEl) { replyEl.value = journalId; }
    if (target) { target.textContent = labels.replyTarget.replace('%{indice}', indice); }
    if (quoteEl) { quoteEl.checked = (form.getAttribute('data-sendmail-quote-default') || '1') === '1'; }
    if (row) { row.style.display = ''; }
  }

  function clearReplyReference(form) {
    var replyEl = form.querySelector('[data-sendmail-reply-journal-id]');
    var row = form.querySelector('[data-sendmail-quote-row]');
    if (replyEl) { replyEl.value = ''; }
    if (row) { row.style.display = 'none'; }
    scheduleLivePreview(form);
  }

  // ---- live header / footer around the comment textarea ------------------
  //
  // Shows the automatically added greeting (header) above and the closing /
  // signature / quoted comment (footer) below the textarea — like a mail
  // client — so nobody types "hallo fritz" twice.

  function findBodyTextarea() {
    var hostForm = findIssueForm();
    if (!hostForm) { return null; }
    return hostForm.querySelector('textarea[name="issue[notes]"]') ||
           hostForm.querySelector('textarea[name="issue[description]"]');
  }

  function ensureLiveBlocks(form) {
    var ta = findBodyTextarea();
    if (!ta) { return null; }
    var hostForm = findIssueForm();
    var header = hostForm.querySelector('[data-sendmail-live-header]');
    var footer = hostForm.querySelector('[data-sendmail-live-footer]');
    if (header && footer) { return { header: header, footer: footer }; }
    var block = (ta.closest && ta.closest('.jstBlock')) || ta;
    var parent = block.parentNode;
    if (!parent) { return null; }
    if (!header) {
      header = document.createElement('pre');
      header.className = 'redmine-sendmail-live redmine-sendmail-live-header';
      header.setAttribute('data-sendmail-live-header', '');
      header.style.display = 'none';
      parent.insertBefore(header, block);
    }
    if (!footer) {
      footer = document.createElement('pre');
      footer.className = 'redmine-sendmail-live redmine-sendmail-live-footer';
      footer.setAttribute('data-sendmail-live-footer', '');
      footer.style.display = 'none';
      if (block.nextSibling) { parent.insertBefore(footer, block.nextSibling); } else { parent.appendChild(footer); }
    }
    return { header: header, footer: footer };
  }

  var livePreviewTimer = null;
  var livePreviewSeq = 0;

  function scheduleLivePreview(form) {
    if (livePreviewTimer) { clearTimeout(livePreviewTimer); }
    livePreviewTimer = setTimeout(function () { refreshLivePreview(form); }, 350);
  }

  function refreshLivePreview(form) {
    var blocks = ensureLiveBlocks(form);
    if (!blocks) { return; }
    if (!hasAnyRecipient(form)) {
      blocks.header.style.display = 'none';
      blocks.footer.style.display = 'none';
      return;
    }
    var state = gatherFormState(form);
    state.body = '';
    state.attachments = [];
    var seq = ++livePreviewSeq;
    requestPreview(form, state).then(function (data) {
      if (seq !== livePreviewSeq) { return; }
      var header = (data.header || '').replace(/\s+$/, '');
      var footer = (data.footer || '').replace(/^\s+/, '');
      blocks.header.textContent = header;
      blocks.footer.textContent = footer;
      blocks.header.style.display = header ? '' : 'none';
      blocks.footer.style.display = footer ? '' : 'none';
    }).catch(function () {
      blocks.header.style.display = 'none';
      blocks.footer.style.display = 'none';
    });
  }

  // ---- "reply by e-mail" links under the comments -------------------------

  function parseJsonAttr(el, name) {
    try { return JSON.parse(el.getAttribute(name) || '[]') || []; } catch (e) { return []; }
  }

  function clearRecipientSelection(form) {
    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]');
    for (var i = 0; i < checkboxes.length; i++) { checkboxes[i].checked = false; }
    var btns = form.querySelectorAll('[data-sendmail-mode-btn]');
    for (var j = 0; j < btns.length; j++) {
      btns[j].classList.remove('active');
      btns[j].setAttribute('aria-pressed', 'false');
    }
    var rows = form.querySelectorAll('[data-sendmail-adhoc-row]');
    for (var k = 0; k < rows.length; k++) { rows[k].parentNode.removeChild(rows[k]); }
  }

  function selectContact(form, id, mode) {
    var btn = form.querySelector('[data-sendmail-mode-btn="' + id + '"][data-mode="' + (mode || 'to') + '"]');
    if (!btn) { return false; }
    if (!btn.classList.contains('active')) { btn.click(); }
    return true;
  }

  function addAdhocRecipient(form, entry) {
    var addBtn = form.querySelector('[data-sendmail-adhoc-add]');
    var rowsContainer = form.querySelector('[data-sendmail-adhoc-rows]');
    if (!addBtn || !rowsContainer) { return; }
    addBtn.click();
    var rows = rowsContainer.querySelectorAll('[data-sendmail-adhoc-row]');
    var row = rows[rows.length - 1];
    if (!row) { return; }
    var emailEl = row.querySelector('.redmine-sendmail-adhoc-email');
    var nameEl  = row.querySelector('.redmine-sendmail-adhoc-name');
    var modeEl  = row.querySelector('.redmine-sendmail-adhoc-mode');
    if (emailEl) { emailEl.value = entry.email || ''; }
    if (nameEl)  { nameEl.value  = entry.name  || ''; }
    if (modeEl)  { modeEl.value  = entry.mode  || 'to'; }
    updateCreateContactLink(form, row);
  }

  function handleReplyClick(replyEl) {
    var hostForm = findIssueForm();
    var form = hostForm ? hostForm.querySelector('[data-sendmail-form]') : null;
    if (!hostForm || !form) { return; }
    var labels = getLabels(form);

    // Reveal Redmine's (initially hidden) update form.
    var update = document.getElementById('update');
    if (update) { update.style.display = ''; }

    clearRecipientSelection(form);
    parseJsonAttr(replyEl, 'data-reply-contacts').forEach(function (c) {
      selectContact(form, String(c.id), c.mode);
    });
    parseJsonAttr(replyEl, 'data-reply-adhoc').forEach(function (a) {
      if (a && a.email) { addAdhocRecipient(form, a); }
    });

    var subjectInput = form.querySelector('[data-sendmail-subject]');
    if (subjectInput) { subjectInput.value = replyEl.getAttribute('data-reply-subject') || ''; }

    setReplyReference(form,
                      replyEl.getAttribute('data-journal-id') || '',
                      replyEl.getAttribute('data-journal-indice') || '',
                      labels);
    updateAfterChange(form);

    var ta = findBodyTextarea();
    var fieldset = form.querySelector('fieldset');
    if (fieldset && fieldset.classList.contains('collapsed')) {
      var legend = fieldset.querySelector('legend');
      if (legend) { legend.click(); }
    }
    if (ta) {
      ta.scrollIntoView({ behavior: 'smooth', block: 'center' });
      ta.focus({ preventScroll: true });
    } else {
      form.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  function wireReplyLinks() {
    var replies = document.querySelectorAll('[data-sendmail-reply]');
    for (var i = 0; i < replies.length; i++) {
      if (replies[i].dataset.sendmailReplyWired === '1') { continue; }
      replies[i].dataset.sendmailReplyWired = '1';
      var link = replies[i].querySelector('.redmine-sendmail-reply-link');
      if (!link) { continue; }
      link.addEventListener('click', (function (el) {
        return function (e) { e.preventDefault(); handleReplyClick(el); };
      })(replies[i]));
    }
  }

  function hasAnyRecipient(form) {
    var anyContact = form.querySelectorAll('[data-sendmail-recipient]:checked').length > 0;
    var adhocEmails = form.querySelectorAll('.redmine-sendmail-adhoc-email');
    for (var i = 0; i < adhocEmails.length; i++) {
      if (adhocEmails[i].value.trim().length > 0) { return true; }
    }
    return anyContact;
  }

  function gatherFormState(form) {
    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]');
    var contactIds = [];
    var modes = {};
    for (var i = 0; i < checkboxes.length; i++) {
      if (!checkboxes[i].checked) { continue; }
      contactIds.push(checkboxes[i].value);
      var modeSel = form.querySelector('[data-sendmail-mode-for="' + checkboxes[i].value + '"]');
      modes[checkboxes[i].value] = modeSel ? modeSel.value : 'to';
    }

    var adhocRows = form.querySelectorAll('[data-sendmail-adhoc-row]');
    var adhoc = [];
    for (var j = 0; j < adhocRows.length; j++) {
      var emailEl = adhocRows[j].querySelector('.redmine-sendmail-adhoc-email');
      if (!emailEl || !emailEl.value.trim()) { continue; }
      var nameEl = adhocRows[j].querySelector('.redmine-sendmail-adhoc-name');
      var modeEl = adhocRows[j].querySelector('.redmine-sendmail-adhoc-mode');
      adhoc.push({
        email: emailEl.value.trim(),
        name:  nameEl ? nameEl.value.trim() : '',
        mode:  modeEl ? modeEl.value : 'to'
      });
    }

    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var subject = subjectInput ? subjectInput.value : '';
    var options = getOptionState(form);

    var hostForm = findIssueForm();
    var bodyValue = '';
    var ticketSubject = '';
    var attachments = [];
    if (hostForm) {
      var notesEl = hostForm.querySelector('textarea[name="issue[notes]"]');
      var descEl  = hostForm.querySelector('textarea[name="issue[description]"]');
      bodyValue = (notesEl && notesEl.value.trim().length ? notesEl.value : '') ||
                  (descEl  && descEl.value)  || '';
      var subjEl = hostForm.querySelector('input[name="issue[subject]"]');
      if (subjEl) { ticketSubject = subjEl.value; }
      // Redmine's attachment upload UI stores each staged file's name in an
      // <input class="filename"> inside .attachments_fields (both pending
      // uploads with a token AND already-saved attachments with an id).
      var fnInputs = hostForm.querySelectorAll('.attachments_fields input.filename');
      for (var k = 0; k < fnInputs.length; k++) {
        var v = (fnInputs[k].value || '').trim();
        if (v) { attachments.push(v); }
      }
    }
    return {
      contactIds:    contactIds,
      contactModes:  modes,
      adhoc:         adhoc,
      subject:       subject,
      body:          bodyValue,
      ticketSubject: ticketSubject,
      attachments:   attachments,
      options:       options
    };
  }

  function buildModal() {
    var existing = document.getElementById('redmine-sendmail-preview-modal');
    if (existing) { return existing; }
    var html =
      '<div id="redmine-sendmail-preview-modal" class="redmine-sendmail-preview-modal" role="dialog" aria-modal="true">' +
      '  <div class="redmine-sendmail-preview-content">' +
      '    <h3 class="redmine-sendmail-preview-heading"></h3>' +
      '    <div class="redmine-sendmail-preview-stage1">' +
      '      <p class="redmine-sendmail-stage1-intro"></p>' +
      '      <div class="redmine-sendmail-stage1-lists"></div>' +
      '    </div>' +
      '    <div class="redmine-sendmail-preview-stage2" style="display:none;">' +
      '      <div class="redmine-sendmail-preview-meta"></div>' +
      '      <div class="redmine-sendmail-preview-subject-row">' +
      '        <strong></strong> <span class="redmine-sendmail-preview-subject"></span>' +
      '      </div>' +
      '      <div class="redmine-sendmail-preview-body"></div>' +
      '      <div class="redmine-sendmail-preview-attachments-row" style="display:none;">' +
      '        <strong></strong>' +
      '        <span class="redmine-sendmail-preview-attachments"></span>' +
      '      </div>' +
      '    </div>' +
      '    <div class="redmine-sendmail-preview-actions">' +
      '      <button type="button" class="redmine-sendmail-preview-edit"></button>' +
      '      <button type="button" class="redmine-sendmail-preview-next"></button>' +
      '      <button type="button" class="redmine-sendmail-preview-send" style="display:none;"></button>' +
      '    </div>' +
      '    <div class="redmine-sendmail-preview-error" style="display:none;"></div>' +
      '  </div>' +
      '</div>';
    var div = document.createElement('div');
    div.innerHTML = html;
    var modal = div.firstChild;
    document.body.appendChild(modal);
    return modal;
  }

  // Renders the mail text as header / comment / footer / quote sections so
  // the automatically added parts are distinguishable from the typed comment.
  function renderPreviewBody(container, data, labels) {
    container.innerHTML = '';
    if (data.header === undefined && data.footer === undefined) {
      var pre = document.createElement('pre');
      pre.className = 'redmine-sendmail-preview-part-text';
      pre.textContent = data.body || '';
      container.appendChild(pre);
      return;
    }
    function part(kind, label, text) {
      if (text == null || String(text).replace(/\s+/g, '') === '') { return; }
      var box = document.createElement('div');
      box.className = 'redmine-sendmail-preview-part redmine-sendmail-preview-part-' + kind;
      var head = document.createElement('div');
      head.className = 'redmine-sendmail-preview-part-label';
      head.textContent = label;
      var pre = document.createElement('pre');
      pre.className = 'redmine-sendmail-preview-part-text';
      pre.textContent = String(text).replace(/^\n+|\n+$/g, '');
      box.appendChild(head);
      box.appendChild(pre);
      container.appendChild(box);
    }
    var footer = data.footer || '';
    var quote = data.quote || '';
    if (quote && footer.indexOf(quote) !== -1) {
      footer = footer.replace(quote, '');
    }
    part('header',  labels.header,  data.header);
    part('comment', labels.comment, data.comment);
    part('footer',  labels.footer,  footer);
    part('quote',   labels.quote,   quote);
  }

  function renderRecipientGroup(parent, label, list) {
    if (!list || !list.length) { return; }
    var box = document.createElement('div');
    box.className = 'redmine-sendmail-stage1-group';
    var head = document.createElement('div');
    head.className = 'redmine-sendmail-stage1-grouplabel';
    head.textContent = label + ' (' + list.length + ')';
    box.appendChild(head);
    var ul = document.createElement('ul');
    ul.className = 'redmine-sendmail-stage1-list';
    list.forEach(function (r) {
      var li = document.createElement('li');
      li.className = 'redmine-sendmail-stage1-item';
      var nameSpan = document.createElement('span');
      nameSpan.className = 'redmine-sendmail-stage1-name';
      nameSpan.textContent = r.name || '';
      var emailSpan = document.createElement('span');
      emailSpan.className = 'redmine-sendmail-stage1-email';
      emailSpan.textContent = '<' + (r.email || '') + '>';
      li.appendChild(nameSpan);
      li.appendChild(document.createTextNode(' '));
      li.appendChild(emailSpan);
      if (r.adhoc) {
        var b = document.createElement('span');
        b.className = 'redmine-sendmail-stage1-adhoc';
        b.textContent = '✎';
        li.appendChild(document.createTextNode(' '));
        li.appendChild(b);
      }
      ul.appendChild(li);
    });
    box.appendChild(ul);
    parent.appendChild(box);
  }

  function showModal(form, data, labels) {
    var modal = buildModal();
    modal.querySelector('.redmine-sendmail-preview-heading').textContent = labels.stage1Heading;

    // Stage 1
    var s1 = modal.querySelector('.redmine-sendmail-preview-stage1');
    var s2 = modal.querySelector('.redmine-sendmail-preview-stage2');
    s1.style.display = '';
    s2.style.display = 'none';
    modal.querySelector('.redmine-sendmail-stage1-intro').textContent = labels.stage1Intro
      .replace('%{count}', data.recipient_count || 0);
    var lists = modal.querySelector('.redmine-sendmail-stage1-lists');
    lists.innerHTML = '';
    renderRecipientGroup(lists, labels.to,  data.to_recipients);
    renderRecipientGroup(lists, labels.cc,  data.cc_recipients);
    renderRecipientGroup(lists, labels.bcc, data.bcc_recipients);

    // Stage 2 (pre-populate so the second click is just a reveal)
    var meta = s2.querySelector('.redmine-sendmail-preview-meta');
    meta.innerHTML = '';
    function addRow(k, v) {
      if (v == null || v === '') { return; }
      var p = document.createElement('div');
      var b = document.createElement('strong');
      b.textContent = k + ': ';
      p.appendChild(b);
      p.appendChild(document.createTextNode(v));
      meta.appendChild(p);
    }
    var first = data.first_recipient || {};
    addRow(labels.to,       (first.name ? first.name + ' <' + first.email + '>' : first.email));
    addRow(labels.from,     (data.from_name ? data.from_name + ' <' + data.from + '>' : data.from));
    addRow(labels.replyTo,  data.reply_to);
    if (data.recipient_count && data.recipient_count > 1) {
      var note = document.createElement('div');
      note.className = 'redmine-sendmail-preview-multi-note';
      note.textContent = labels.multiRecipient.replace('%{count}', data.recipient_count);
      meta.appendChild(note);
    }
    s2.querySelector('.redmine-sendmail-preview-subject-row strong').textContent = labels.subject + ':';
    s2.querySelector('.redmine-sendmail-preview-subject').textContent = data.subject;
    renderPreviewBody(s2.querySelector('.redmine-sendmail-preview-body'), data, labels);

    // Attachment list — pull the row placeholder we injected in buildModal(),
    // hide it entirely when nothing is attached, otherwise fill with chip
    // spans (filenames only, no thumbnails).
    var attachRow = s2.querySelector('.redmine-sendmail-preview-attachments-row');
    if (attachRow) {
      var atts = data.attachments || [];
      if (atts.length === 0) {
        attachRow.style.display = 'none';
      } else {
        attachRow.style.display = '';
        var label = attachRow.querySelector('strong');
        var list  = attachRow.querySelector('.redmine-sendmail-preview-attachments');
        if (label) { label.textContent = labels.attachments + ':'; }
        if (list) {
          list.innerHTML = '';
          atts.forEach(function (name) {
            var chip = document.createElement('span');
            chip.className = 'redmine-sendmail-attachment-name';
            chip.textContent = name;
            list.appendChild(chip);
          });
        }
      }
    }

    modal.querySelector('.redmine-sendmail-preview-error').style.display = 'none';

    var edit = modal.querySelector('.redmine-sendmail-preview-edit');
    var next = modal.querySelector('.redmine-sendmail-preview-next');
    var send = modal.querySelector('.redmine-sendmail-preview-send');
    edit.textContent = labels.edit;
    next.textContent = labels.stage1Continue;
    next.style.display = '';
    send.textContent = labels.send;
    send.style.display = 'none';

    function hide() { modal.classList.remove('active'); }

    edit.onclick = function () { hide(); };
    next.onclick = function () {
      s1.style.display = 'none';
      s2.style.display = '';
      modal.querySelector('.redmine-sendmail-preview-heading').textContent = labels.heading;
      next.style.display = 'none';
      send.style.display = '';
    };
    send.onclick = function () {
      var hostForm = findIssueForm();
      if (!hostForm) { return; }
      // Re-enable the save button defensively (in case anything disabled it).
      var btn = findSaveButton(hostForm);
      if (btn && btn.disabled) { btn.disabled = false; }
      // Replace the modal content with a "Sending..." message so the user gets
      // immediate feedback during the form-submit -> server-processing ->
      // redirect cycle (typically ~1 second). The modal hides itself when the
      // browser navigates to the response page.
      var s1 = modal.querySelector('.redmine-sendmail-preview-stage1');
      var s2 = modal.querySelector('.redmine-sendmail-preview-stage2');
      if (s1) { s1.style.display = 'none'; }
      if (s2) { s2.style.display = 'none'; }
      modal.querySelector('.redmine-sendmail-preview-heading').textContent =
        (labels.sending || 'Wird gesendet…');
      var actions = modal.querySelector('.redmine-sendmail-preview-actions');
      if (actions) { actions.style.display = 'none'; }
      var sending = modal.querySelector('.redmine-sendmail-preview-sending');
      if (!sending) {
        sending = document.createElement('div');
        sending.className = 'redmine-sendmail-preview-sending';
        modal.querySelector('.redmine-sendmail-preview-content').appendChild(sending);
      }
      sending.style.display = '';
      sending.textContent = labels.sending || 'Wird gesendet…';
      // Use form.submit() directly: it is the only call that *unconditionally*
      // posts the form, bypassing every submit-event listener (incl. our own
      // preview interceptor) and any UJS/Stimulus/jQuery delegates that might
      // preventDefault.
      try {
        if (window.jQuery) { window.jQuery('textarea', hostForm).removeData('changed'); }
      } catch (e) { /* ignore */ }
      hostForm.submit();
    };
    modal.classList.add('active');
  }

  function showModalError(message, labels) {
    var modal = buildModal();
    modal.querySelector('.redmine-sendmail-preview-heading').textContent = labels.heading;
    var s1 = modal.querySelector('.redmine-sendmail-preview-stage1');
    var s2 = modal.querySelector('.redmine-sendmail-preview-stage2');
    if (s1) { s1.style.display = 'none'; }
    if (s2) { s2.style.display = 'none'; }
    var err = modal.querySelector('.redmine-sendmail-preview-error');
    err.textContent = message;
    err.style.display = '';
    modal.querySelector('.redmine-sendmail-preview-send').style.display = 'none';
    modal.querySelector('.redmine-sendmail-preview-next').style.display = 'none';
    modal.querySelector('.redmine-sendmail-preview-edit').textContent = labels.close;
    modal.querySelector('.redmine-sendmail-preview-edit').onclick = function () {
      modal.classList.remove('active');
    };
    modal.classList.add('active');
  }

  function getPreviewUrl(form) {
    return form.getAttribute('data-sendmail-preview-url') || '';
  }

  function getLabels(form) {
    return {
      heading:        form.getAttribute('data-sendmail-label-heading')         || 'Mail preview',
      stage1Heading:  form.getAttribute('data-sendmail-label-stage1-heading')  || 'Confirm recipients',
      stage1Intro:    form.getAttribute('data-sendmail-label-stage1-intro')    || 'You are about to send mail to %{count} recipients. Please verify:',
      stage1Continue: form.getAttribute('data-sendmail-label-stage1-continue') || 'Continue to preview',
      subject:        form.getAttribute('data-sendmail-label-subject')         || 'Subject',
      from:           form.getAttribute('data-sendmail-label-from')            || 'From',
      to:             form.getAttribute('data-sendmail-label-to')              || 'TO',
      cc:             form.getAttribute('data-sendmail-label-cc')              || 'CC',
      bcc:            form.getAttribute('data-sendmail-label-bcc')             || 'BCC',
      replyTo:        form.getAttribute('data-sendmail-label-reply-to')        || 'Reply-To',
      send:           form.getAttribute('data-sendmail-label-send')            || 'Send',
      edit:           form.getAttribute('data-sendmail-label-edit')            || 'Edit',
      close:          form.getAttribute('data-sendmail-label-close')           || 'Close',
      sending:        form.getAttribute('data-sendmail-label-sending')         || 'Wird gesendet…',
      attachments:    form.getAttribute('data-sendmail-label-attachments')     || 'Anhänge',
      multiRecipient: form.getAttribute('data-sendmail-label-multi')           || '%{count} recipients — preview shows the first.',
      header:         form.getAttribute('data-sendmail-label-header')          || 'Header',
      footer:         form.getAttribute('data-sendmail-label-footer')          || 'Footer',
      quote:          form.getAttribute('data-sendmail-label-quote')           || 'Quoted comment',
      comment:        form.getAttribute('data-sendmail-label-comment')         || 'Comment',
      replyTarget:    form.getAttribute('data-sendmail-label-reply-target')    || 'comment #%{indice}'
    };
  }

  function requestPreview(form, state) {
    var url = getPreviewUrl(form);
    if (!url) { return Promise.reject(new Error('no_preview_url')); }
    var fd = new FormData();
    state.contactIds.forEach(function (id) { fd.append('sendmail[contact_ids][]', id); });
    Object.keys(state.contactModes).forEach(function (id) {
      fd.append('sendmail[contact_modes][' + id + ']', state.contactModes[id]);
    });
    state.adhoc.forEach(function (row, i) {
      fd.append('sendmail[adhoc][' + i + '][email]', row.email);
      fd.append('sendmail[adhoc][' + i + '][name]',  row.name);
      fd.append('sendmail[adhoc][' + i + '][mode]',  row.mode);
    });
    (state.attachments || []).forEach(function (name) {
      fd.append('attachments[]', name);
    });
    var o = state.options || {};
    if (o.formOfAddress) { fd.append('sendmail[form_of_address]', o.formOfAddress); }
    fd.append('sendmail[first_name_only]', o.firstNameOnly ? '1' : '0');
    fd.append('sendmail[quote]', o.quote ? '1' : '0');
    fd.append('sendmail[reply_journal_id]', o.replyJournalId || '');
    fd.append('sendmail[subject]', state.subject || '');
    fd.append('subject', state.subject || '');
    fd.append('body', state.body || '');
    fd.append('ticket_subject', state.ticketSubject || '');
    var issueIdEl = (findIssueForm() || document).querySelector('input[name="id"]');
    if (issueIdEl) { fd.append('issue_id', issueIdEl.value); }
    return fetch(url, {
      method: 'POST',
      headers: { 'X-CSRF-Token': csrfToken(), 'Accept': 'application/json' },
      credentials: 'same-origin',
      body: fd
    }).then(function (r) {
      if (!r.ok) { return r.json().then(function (j) { throw new Error(j.error || 'http_' + r.status); }); }
      return r.json();
    });
  }

  function wirePreview(form) {
    var hostForm = findIssueForm();
    if (!hostForm) { return; }
    // `init()` runs on DOMContentLoaded AND on every jQuery `ajax:complete`
    // (Redmine fires many AJAX calls for sidebars). Without this guard the
    // submit listener gets attached N times — listener #1 clears the
    // flag, listener #2..N then see no flag and preventDefault the submit,
    // so the "Send" button in the preview modal never actually submits.
    if (hostForm.dataset.sendmailPreviewWired === '1') { return; }
    hostForm.dataset.sendmailPreviewWired = '1';
    var labels = getLabels(form);

    hostForm.addEventListener('submit', function (event) {
      if (hostForm.dataset[SENDMAIL_PREVIEW_FLAG] === '1') {
        delete hostForm.dataset[SENDMAIL_PREVIEW_FLAG];
        return;
      }
      var state = gatherFormState(form);
      if (state.contactIds.length === 0 && state.adhoc.length === 0) { return; }
      event.preventDefault();
      requestPreview(form, state).then(function (data) {
        showModal(form, data, labels);
      }).catch(function (err) {
        showModalError(labels.heading + ': ' + (err && err.message ? err.message : 'error'), labels);
      });
    }, true);
  }

  function wireForm(form) {
    // Same multi-init protection as wirePreview: don't double-attach the
    // checkbox/mode-button/search/adhoc listeners.
    if (form.dataset.sendmailWired === '1') { return; }
    form.dataset.sendmailWired = '1';

    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]');
    if (!checkboxes.length && !form.querySelector('[data-sendmail-adhoc]')) { return; }

    for (var i = 0; i < checkboxes.length; i++) {
      checkboxes[i].addEventListener('change', function () { updateAfterChange(form); });
    }
    wireModeButtons(form);
    wireSearch(form);
    wireAdhoc(form);
    wireOptions(form);
    wirePreview(form);
    updateAfterChange(form);
  }

  // Each recipient row has three mutually-exclusive TO/CC/BCC buttons.
  // Clicking a button selects that mode and marks the contact as recipient.
  // Clicking the already-active button deselects the contact entirely.
  function wireModeButtons(form) {
    var buttons = form.querySelectorAll('[data-sendmail-mode-btn]');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener('click', function (e) {
        var btn = e.currentTarget;
        var cid = btn.getAttribute('data-sendmail-mode-btn');
        var mode = btn.getAttribute('data-mode');
        var checkbox = form.querySelector('#sendmail_contact_' + cid);
        var modeInput = form.querySelector('#sendmail_contact_mode_' + cid);
        var groupBtns = form.querySelectorAll('[data-sendmail-mode-btn="' + cid + '"]');
        var wasActive = btn.classList.contains('active');

        // Clear active state on all buttons in this row.
        for (var j = 0; j < groupBtns.length; j++) {
          groupBtns[j].classList.remove('active');
          groupBtns[j].setAttribute('aria-pressed', 'false');
        }

        if (wasActive) {
          // Re-clicking the active button deselects the contact.
          if (checkbox) { checkbox.checked = false; }
        } else {
          btn.classList.add('active');
          btn.setAttribute('aria-pressed', 'true');
          if (modeInput) { modeInput.value = mode; }
          if (checkbox && !checkbox.checked) { checkbox.checked = true; }
        }
        // Dispatch change so the recipient-count / save-button label updates.
        if (checkbox) {
          var ev = document.createEvent('Event');
          ev.initEvent('change', true, true);
          checkbox.dispatchEvent(ev);
        }
        updateAfterChange(form);
      });
    }
  }

  function initRecipientForm() {
    var forms = document.querySelectorAll('[data-sendmail-form]');
    for (var i = 0; i < forms.length; i++) {
      wireForm(forms[i]);
    }
  }

  function highlightSentJournals() {
    var markers = document.querySelectorAll('[data-sendmail-marker]');
    for (var i = 0; i < markers.length; i++) {
      var journal = markers[i].closest ? markers[i].closest('.journal') : null;
      if (journal && !journal.classList.contains('redmine-sendmail-sent')) {
        journal.classList.add('redmine-sendmail-sent');
      }
    }
  }

  function init() {
    initRecipientForm();
    highlightSentJournals();
    wireReplyLinks();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  if (window.jQuery) {
    // Redmine's new-issue form fires `$.ajax` on tracker/category/etc changes
    // (form_update_triggered_by) which replaces the attributes area — including
    // our recipient picker — without any DOM-remove/insert event we could hook.
    // jQuery raises the camelCase `ajaxComplete` event on every raw $.ajax
    // call; the colon-form `ajax:complete` is only fired by jquery-ujs for
    // data-remote elements, which Redmine's issue form doesn't use — so we
    // listen to both. init() is idempotent via the data-sendmail-wired guards.
    window.jQuery(document).on('ajax:complete ajaxComplete', init);
  }

  // As a belt-and-suspenders defence against future Redmine changes that
  // replace the sendmail form via a code path we don't recognise, observe DOM
  // mutations and re-init when a fresh [data-sendmail-form] appears.
  if (typeof MutationObserver === 'function') {
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        for (var j = 0; j < m.addedNodes.length; j++) {
          var node = m.addedNodes[j];
          if (node.nodeType !== 1) { continue; }
          if (node.matches && node.matches('[data-sendmail-form]')) { init(); return; }
          if (node.querySelector && node.querySelector('[data-sendmail-form]')) { init(); return; }
        }
      }
    });
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
    } else {
      document.addEventListener('DOMContentLoaded', function () {
        observer.observe(document.body, { childList: true, subtree: true });
      });
    }
  }
})();
