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

  # Renders a small "📎 N" badge with the joined filenames as tooltip — used in
  # the dispatch index where space is tight. Returns nil when no attachments.
  def sendmail_attachment_badge(dispatch)
    names = dispatch.attachment_filenames_list
    return nil if names.empty?
    content_tag(:span,
                "📎 #{names.size}",
                class: 'redmine-sendmail-attachment-badge',
                title: names.join("\n"))
  end

  # Renders the filenames as plain text — one filename per line — used on the
  # dispatch detail page. Returns the empty-attachments label when none.
  def sendmail_attachment_list(dispatch)
    names = dispatch.attachment_filenames_list
    if names.empty?
      content_tag(:em, l(:label_sendmail_no_attachments), class: 'redmine-sendmail-empty')
    else
      safe_join(names.map { |n| content_tag(:span, n, class: 'redmine-sendmail-attachment-name') }, tag.br)
    end
  end

  def sendmail_mode_label(dispatch)
    mode = dispatch.respond_to?(:mode) ? dispatch.mode.to_s : 'to'
    key  = "label_sendmail_mode_#{mode.presence || 'to'}"
    content_tag(:span, l(key.to_sym, default: mode.upcase),
                class:   "redmine-sendmail-mode redmine-sendmail-mode-#{mode.presence || 'to'}",
                title:   l(:label_sendmail_mode_tooltip, default: ''))
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
