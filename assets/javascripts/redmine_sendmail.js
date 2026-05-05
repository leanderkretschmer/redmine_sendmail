(function () {
  'use strict';

  function initRecipientForm() {
    var form = document.querySelector('[data-sendmail-form]');
    if (!form) { return; }
    var checkboxes = form.querySelectorAll('[data-sendmail-recipient]');
    var subjectRow = form.querySelector('[data-sendmail-subject-row]');
    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var hint = form.querySelector('[data-sendmail-hint]');
    if (!checkboxes.length || !subjectRow || !subjectInput) { return; }

    function anyChecked() {
      for (var i = 0; i < checkboxes.length; i++) {
        if (checkboxes[i].checked) { return true; }
      }
      return false;
    }

    function update() {
      var visible = anyChecked();
      subjectRow.style.display = visible ? '' : 'none';
      if (hint) { hint.style.display = visible ? '' : 'none'; }
      if (visible) {
        subjectInput.required = true;
      } else {
        subjectInput.required = false;
        subjectInput.value = '';
      }
    }

    for (var i = 0; i < checkboxes.length; i++) {
      checkboxes[i].addEventListener('change', update);
    }
    update();
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
