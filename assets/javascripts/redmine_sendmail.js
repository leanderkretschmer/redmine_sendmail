(function () {
  'use strict';

  function init() {
    var form = document.querySelector('[data-sendmail-form]');
    if (!form) { return; }
    var select = form.querySelector('[data-sendmail-recipient]');
    var subjectRow = form.querySelector('[data-sendmail-subject-row]');
    var subjectInput = form.querySelector('[data-sendmail-subject]');
    var hint = form.querySelector('[data-sendmail-hint]');
    if (!select || !subjectRow || !subjectInput) { return; }

    function update() {
      var hasRecipient = select.value && select.value.length > 0;
      subjectRow.style.display = hasRecipient ? '' : 'none';
      if (hint) { hint.style.display = hasRecipient ? '' : 'none'; }
      if (hasRecipient) {
        subjectInput.required = true;
      } else {
        subjectInput.required = false;
        subjectInput.value = '';
      }
    }

    select.addEventListener('change', update);
    update();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
