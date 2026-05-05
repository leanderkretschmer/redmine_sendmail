class RedmineSendmailMailer < ActionMailer::Base
  default content_type: 'text/plain', charset: 'UTF-8'

  def dispatch(subject:, body:, recipient_email:, recipient_name: nil, from_email: nil, reply_to: nil, extra_headers: {}, smtp_config: nil)
    to_header = recipient_name.present? ? %("#{recipient_name}" <#{recipient_email}>) : recipient_email

    headers = {
      to:           to_header,
      subject:      subject,
      content_type: 'text/plain'
    }
    headers[:from]     = from_email if from_email.present?
    headers[:reply_to] = reply_to   if reply_to.present?
    headers.merge!(extra_headers) if extra_headers.is_a?(Hash)

    @body_text = body.to_s

    message = mail(headers) do |format|
      format.text { render plain: @body_text }
    end

    if smtp_config.is_a?(Hash) && smtp_config[:address].present?
      message.delivery_method(:smtp, smtp_config)
    end
    message
  end
end
