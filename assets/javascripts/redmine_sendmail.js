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
           (document.getElementById('sendmail_contact_1')
              ? document.getElementById('sendmail_contact_1').closest('form')
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

  function gatherFormState(form) {
    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]:checked');
    var contactIds = [];
    for (var i = 0; i < checkboxes.length; i++) { contactIds.push(checkboxes[i].value); }

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
      '    <div class="redmine-sendmail-preview-meta"></div>' +
      '    <div class="redmine-sendmail-preview-subject-row">' +
      '      <strong></strong> <span class="redmine-sendmail-preview-subject"></span>' +
      '    </div>' +
      '    <pre class="redmine-sendmail-preview-body"></pre>' +
      '    <div class="redmine-sendmail-preview-actions">' +
      '      <button type="button" class="redmine-sendmail-preview-edit"></button>' +
      '      <button type="button" class="redmine-sendmail-preview-send"></button>' +
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

  function showModal(form, data, labels) {
    var modal = buildModal();
    modal.querySelector('.redmine-sendmail-preview-heading').textContent = labels.heading;
    var meta = modal.querySelector('.redmine-sendmail-preview-meta');
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
    addRow(labels.to,        (data.recipient_name ? data.recipient_name + ' <' + data.recipient_email + '>' : data.recipient_email));
    addRow(labels.from,      (data.from_name ? data.from_name + ' <' + data.from + '>' : data.from));
    addRow(labels.replyTo,   data.reply_to);
    if (data.recipient_count && data.recipient_count > 1) {
      var note = document.createElement('div');
      note.className = 'redmine-sendmail-preview-multi-note';
      note.textContent = labels.multiRecipient.replace('%{count}', data.recipient_count);
      meta.appendChild(note);
    }
    modal.querySelector('.redmine-sendmail-preview-subject-row strong').textContent = labels.subject + ':';
    modal.querySelector('.redmine-sendmail-preview-subject').textContent = data.subject;
    modal.querySelector('.redmine-sendmail-preview-body').textContent = data.body;
    modal.querySelector('.redmine-sendmail-preview-error').style.display = 'none';

    var edit = modal.querySelector('.redmine-sendmail-preview-edit');
    var send = modal.querySelector('.redmine-sendmail-preview-send');
    edit.textContent = labels.edit;
    send.textContent = labels.send;

    function hide() { modal.classList.remove('active'); }
    edit.onclick = function () { hide(); };
    send.onclick = function () {
      hide();
      var hostForm = findIssueForm();
      if (!hostForm) { return; }
      hostForm.dataset[SENDMAIL_PREVIEW_FLAG] = '1';
      var btn = findSaveButton(hostForm);
      if (btn) {
        btn.click();
      } else {
        hostForm.submit();
      }
    };
    modal.classList.add('active');
  }

  function showModalError(message, labels) {
    var modal = buildModal();
    modal.querySelector('.redmine-sendmail-preview-heading').textContent = labels.heading;
    modal.querySelector('.redmine-sendmail-preview-meta').innerHTML = '';
    modal.querySelector('.redmine-sendmail-preview-subject').textContent = '';
    modal.querySelector('.redmine-sendmail-preview-body').textContent = '';
    var err = modal.querySelector('.redmine-sendmail-preview-error');
    err.textContent = message;
    err.style.display = '';
    modal.querySelector('.redmine-sendmail-preview-send').style.display = 'none';
    modal.querySelector('.redmine-sendmail-preview-edit').textContent = labels.close;
    modal.querySelector('.redmine-sendmail-preview-edit').onclick = function () {
      modal.classList.remove('active');
      modal.querySelector('.redmine-sendmail-preview-send').style.display = '';
    };
    modal.classList.add('active');
  }

  function getPreviewUrl(form) {
    return form.getAttribute('data-sendmail-preview-url') || '';
  }

  function getLabels(form) {
    return {
      heading:        form.getAttribute('data-sendmail-label-heading')   || 'Mail preview',
      subject:        form.getAttribute('data-sendmail-label-subject')   || 'Subject',
      from:           form.getAttribute('data-sendmail-label-from')      || 'From',
      to:             form.getAttribute('data-sendmail-label-to')        || 'To',
      replyTo:        form.getAttribute('data-sendmail-label-reply-to')  || 'Reply-To',
      send:           form.getAttribute('data-sendmail-label-send')      || 'Send',
      edit:           form.getAttribute('data-sendmail-label-edit')      || 'Edit',
      close:          form.getAttribute('data-sendmail-label-close')     || 'Close',
      multiRecipient: form.getAttribute('data-sendmail-label-multi')     || '%{count} recipients — preview shows the first.'
    };
  }

  function requestPreview(form, state) {
    var url = getPreviewUrl(form);
    if (!url) { return Promise.reject(new Error('no_preview_url')); }
    var fd = new FormData();
    state.contactIds.forEach(function (id) { fd.append('sendmail[contact_ids][]', id); });
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
    var labels = getLabels(form);

    hostForm.addEventListener('submit', function (event) {
      if (hostForm.dataset[SENDMAIL_PREVIEW_FLAG] === '1') {
        delete hostForm.dataset[SENDMAIL_PREVIEW_FLAG];
        return;
      }
      var state = gatherFormState(form);
      if (state.contactIds.length === 0) { return; }
      event.preventDefault();
      requestPreview(form, state).then(function (data) {
        showModal(form, data, labels);
      }).catch(function (err) {
        showModalError(labels.heading + ': ' + (err && err.message ? err.message : 'error'), labels);
      });
    }, true);
  }

  function wireForm(form) {
    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]');
    var subjectRow = form.querySelector('[data-sendmail-subject-row]');
    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var hint = form.querySelector('[data-sendmail-hint]');
    if (!checkboxes.length) { return; }

    function anyChecked() {
      for (var i = 0; i < checkboxes.length; i++) {
        if (checkboxes[i].checked) { return true; }
      }
      return false;
    }

    function update() {
      var visible = anyChecked();
      if (subjectRow) { subjectRow.style.display = visible ? '' : 'none'; }
      if (hint) { hint.style.display = visible ? '' : 'none'; }
      if (subjectInput) {
        if (visible) {
          subjectInput.required = true;
        } else {
          subjectInput.required = false;
          subjectInput.value = '';
        }
      }
      updateSaveButtonLabel(form, visible);
    }

    for (var i = 0; i < checkboxes.length; i++) {
      checkboxes[i].addEventListener('change', update);
    }
    update();
    wireSearch(form);
    wirePreview(form);
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
