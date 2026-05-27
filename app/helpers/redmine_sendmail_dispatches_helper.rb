module RedmineSendmailDispatchesHelper
  # Looks up a translated, human-readable explanation for a
  # BounceChecker code (stored in RedmineSendmailDispatch#failure_reason_detail).
  # Returns nil when there is no diagnosis to show.
  def sendmail_failure_reason_label(code)
    return nil if code.blank?
    key = "label_sendmail_failure_#{code}"
    translated = l(key.to_sym, default: '')
    translated.presence
  end

  def sendmail_status_cell(dispatch)
    if dispatch.sent?
      content_tag(:span, l(:label_sendmail_status_sent), class: 'redmine-sendmail-status sent')
    else
      label = content_tag(:span, l(:label_sendmail_status_failed), class: 'redmine-sendmail-status failed')
      reason = sendmail_failure_reason_label(dispatch.failure_reason_detail)
      hint   = [dispatch.error_message.to_s, reason].reject(&:blank?).join(' — ')
      if hint.present?
        label + ' ' + content_tag(:span, 'i',
                                  class: 'redmine-sendmail-failure-info',
                                  title: hint,
                                  tabindex: 0)
      else
        label
      end
    end
  end
end
