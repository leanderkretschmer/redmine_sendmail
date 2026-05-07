module RedmineSendmail
  module TemplateRenderer
    module_function

    PLACEHOLDERS = %w[
      user_name user_login user_firstname user_lastname user_email
      ticket_id ticket_subject ticket_url
      project_name project_identifier projekt_kennung projekt-kennung
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

    def build_vars(user:, issue:, contact:, recipient_email:, recipient_name:, custom_subject:, comment:, settings: nil)
      settings ||= Setting.plugin_redmine_sendmail || {}
      project = issue.project
      identifier = project.identifier.to_s
      projekt_kennung = slice_identifier(identifier, settings['project_identifier_slice'])
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
        'project_identifier'=> identifier,
        'projekt_kennung'   => projekt_kennung,
        'projekt-kennung'   => projekt_kennung,
        'recipient_name'    => recipient_name.to_s,
        'recipient_email'   => recipient_email.to_s,
        'custom_subject'    => custom_subject.to_s,
        'comment'           => comment.to_s,
        'date'              => I18n.l(Date.today)
      }
    end

    # Slices a 1-indexed inclusive character range out of `identifier`.
    # An empty/blank/"all" setting returns the full identifier.
    # "1-8" returns characters 1..8, "4-8" returns characters 4..8, etc.
    def slice_identifier(identifier, range_setting)
      identifier = identifier.to_s
      setting = range_setting.to_s.strip.downcase
      return identifier if setting.empty? || setting == 'all' || setting == 'full'
      if setting =~ /\A(\d+)\s*-\s*(\d+)\z/
        from = Regexp.last_match(1).to_i
        to   = Regexp.last_match(2).to_i
        return identifier if from < 1 || to < from
        identifier[(from - 1)..(to - 1)].to_s
      else
        identifier
      end
    end

    def issue_url(issue)
      host = Setting.host_name.to_s
      proto = Setting.protocol.presence || 'http'
      base = host.include?('://') ? host : "#{proto}://#{host}"
      "#{base.chomp('/')}/issues/#{issue.id}"
    end
  end
end
