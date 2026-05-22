(function () {
  'use strict';

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
      // The notes form has a subject field; the new-issue form does not
      // (the ticket name is used as the subject), so guard each element.
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
    }

    for (var i = 0; i < checkboxes.length; i++) {
      checkboxes[i].addEventListener('change', update);
    }
    update();
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
