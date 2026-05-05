class RedmineSendmailMailer < ActionMailer::Base
  default content_type: 'text/plain', charset: 'UTF-8'

  def dispatch(subject:, body:, recipient_email:, recipient_name: nil, from_email: nil, reply_to: nil, extra_headers: {})
    to_header = recipient_name.present? ? %("#{recipient_name}" <#{recipient_email}>) : recipient_email

    headers = {
      to:           to_header,
      subject:      subject,
      body:         body,
      content_type: 'text/plain'
    }
    headers[:from]     = from_email if from_email.present?
    headers[:reply_to] = reply_to   if reply_to.present?
    headers.merge!(extra_headers) if extra_headers.is_a?(Hash)

    mail(headers)
  end
end
