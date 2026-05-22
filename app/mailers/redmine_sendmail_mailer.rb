class RedmineSendmailMailer < ActionMailer::Base
  default content_type: 'text/plain', charset: 'UTF-8'

  def dispatch(subject:, body:, recipient_email:, recipient_name: nil, from_email: nil, from_name: nil, reply_to: nil, extra_headers: {}, smtp_config: nil, attachments_data: nil)
    to_header   = address_header(recipient_email, recipient_name)
    from_header = address_header(from_email, from_name)

    has_attachments = attachments_data.is_a?(Array) && attachments_data.any?

    headers = {
      to:      to_header,
      subject: subject
    }
    headers[:content_type] = 'text/plain' unless has_attachments
    headers[:from]     = from_header if from_email.present?
    headers[:reply_to] = reply_to    if reply_to.present?
    headers.merge!(extra_headers) if extra_headers.is_a?(Hash)

    if has_attachments
      attachments_data.each do |a|
        next unless a.is_a?(Hash) && a[:filename].present? && a[:content].present?
        attachments[a[:filename]] = {
          mime_type: a[:content_type].presence || 'application/octet-stream',
          content:   a[:content]
        }
      end
    end

    @body_text = body.to_s

    message = mail(headers) do |format|
      format.text { render plain: @body_text }
    end

    if smtp_config.is_a?(Hash) && smtp_config[:address].present?
      message.delivery_method(:smtp, smtp_config)
    end
    message
  end

  private

  # Builds a `"Display Name" <address>` header, falling back to the bare
  # address when no name is given. The display name is sanitised to prevent
  # header injection via template-supplied values.
  def address_header(email, name = nil)
    email = email.to_s.strip
    return email if email.blank?
    clean_name = name.to_s.gsub(/[\r\n"]/, ' ').squeeze(' ').strip
    clean_name.present? ? %("#{clean_name}" <#{email}>) : email
  end
end
