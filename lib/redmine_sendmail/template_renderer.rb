module RedmineSendmail
  module TemplateRenderer
    module_function

    PLACEHOLDERS = %w[
      user_name user_login user_firstname user_lastname user_email
      ticket_id ticket_subject ticket_url
      project_name project_identifier
      recipient_name recipient_email
      custom_subject comment date
    ].freeze

    def render(template, vars)
      return '' if template.blank?
      result = template.to_s.dup
      vars.each do |key, value|
        result.gsub!("{#{key}}", value.to_s)
      end
      result
    end

    def build_vars(user:, issue:, contact:, recipient_email:, recipient_name:, custom_subject:, comment:)
      project = issue.project
      {
        'user_name'         => user.name,
        'user_login'        => user.login,
        'user_firstname'    => user.firstname.to_s,
        'user_lastname'     => user.lastname.to_s,
        'user_email'        => user.mail.to_s,
        'ticket_id'         => issue.id.to_s,
        'ticket_subject'    => issue.subject.to_s,
        'ticket_url'        => issue_url(issue),
        'project_name'      => project.name.to_s,
        'project_identifier'=> project.identifier.to_s,
        'recipient_name'    => recipient_name.to_s,
        'recipient_email'   => recipient_email.to_s,
        'custom_subject'    => custom_subject.to_s,
        'comment'           => comment.to_s,
        'date'              => I18n.l(Date.today)
      }
    end

    def issue_url(issue)
      host = Setting.host_name.to_s
      proto = Setting.protocol.presence || 'http'
      base = host.include?('://') ? host : "#{proto}://#{host}"
      "#{base.chomp('/')}/issues/#{issue.id}"
    end
  end
end
