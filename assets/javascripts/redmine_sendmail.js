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
        inputs[i].addEventListener('input', function () { updateAfterChange(form); });
        inputs[i].addEventListener('change', function () { updateAfterChange(form); });
      }
      updateAfterChange(form);
    }

    addBtn.addEventListener('click', addRow);
  }

  function updateAfterChange(form) {
    var has = hasAnyRecipient(form);
    var subjectRow = form.querySelector('[data-sendmail-subject-row]');
    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var hint = form.querySelector('[data-sendmail-hint]');
    if (subjectRow) { subjectRow.style.display = has ? '' : 'none'; }
    if (hint) { hint.style.display = has ? '' : 'none'; }
    if (subjectInput) {
      if (!has) { subjectInput.value = ''; }
    }
    updateSaveButtonLabel(form, has);
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

    var hostForm = findIssueForm();
    var bodyValue = '';
    var ticketSubject = '';
    if (hostForm) {
      var notesEl = hostForm.querySelector('textarea[name="issue[notes]"]');
      var descEl  = hostForm.querySelector('textarea[name="issue[description]"]');
      bodyValue = (notesEl && notesEl.value.trim().length ? notesEl.value : '') ||
                  (descEl  && descEl.value)  || '';
      var subjEl = hostForm.querySelector('input[name="issue[subject]"]');
      if (subjEl) { ticketSubject = subjEl.value; }
    }
    return {
      contactIds:    contactIds,
      contactModes:  modes,
      adhoc:         adhoc,
      subject:       subject,
      body:          bodyValue,
      ticketSubject: ticketSubject
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
      '      <pre class="redmine-sendmail-preview-body"></pre>' +
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
    s2.querySelector('.redmine-sendmail-preview-body').textContent = data.body;
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
      multiRecipient: form.getAttribute('data-sendmail-label-multi')           || '%{count} recipients — preview shows the first.'
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
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  if (window.jQuery) {
    window.jQuery(document).on('ajax:complete', init);
  }
})();
