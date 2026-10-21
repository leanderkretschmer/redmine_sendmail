require_dependency File.expand_path('reply_helper', __dir__)

module RedmineSendmail
  module TemplateRenderer
    module_function

    PLACEHOLDERS = %w[
      user_name user_login user_firstname user_lastname user_email
      ticket_id ticket_subject ticket_url
      project_name project_identifier projekt_kennung projekt-kennung
      project_info_1 project_info_2 project-info-1 project-info-2
      recipient_name recipient_firstname recipient_lastname recipient_email
      kunden-projekt-kennung kunden_projekt_kennung
      salutation closing form_of_address
      custom_subject comment quote date
    ].freeze

    def render(template, vars)
      return '' if template.blank?
      result = template.to_s.dup
      vars.each do |key, value|
        result.gsub!("{#{key}}", value.to_s)
      end
      result
    end

    # Builds the placeholder hash for one mail.
    #
    # `options` (all optional):
    #   form_of_address: 'du' | 'sie' | nil  — explicit override from the form
    #   first_name_only: true/false          — greet by first name, sign with first name
    #   contact:  Contact or nil             — structured recipient name source
    def build_vars(user:, issue:, contact:, recipient_email:, recipient_name:, custom_subject:, comment:, settings: nil, options: {})
      settings ||= Setting.plugin_redmine_sendmail || {}
      options  ||= {}
      project = issue.project
      identifier = project.identifier.to_s
      projekt_kennung = slice_identifier(identifier, settings['project_identifier_slice'])
      project_info_1, project_info_2 = RedmineSendmailProjectSetting.values_for(project)

      lowercase  = settings['lowercase_recipient_name'].to_s != '0'
      first_only = ReplyHelper.truthy?(options[:first_name_only])
      foa        = ReplyHelper.form_of_address_for(user, settings, options[:form_of_address])
      names      = ReplyHelper.recipient_names(contact: contact,
                                               fallback_name: recipient_name,
                                               lowercase: lowercase,
                                               first_only: first_only)

      vars = {
        'user_name'           => ReplyHelper.user_display_name(user, first_only: first_only),
        'user_login'          => user.login,
        'user_firstname'      => user.firstname.to_s,
        'user_lastname'       => user.lastname.to_s,
        'user_email'          => user.mail.to_s,
        'ticket_id'           => issue.id.to_s,
        'ticket_subject'      => issue.subject.to_s,
        'ticket_url'          => issue_url(issue),
        'project_name'        => project.name.to_s,
        'project_identifier'  => identifier,
        'projekt_kennung'     => projekt_kennung,
        'projekt-kennung'     => projekt_kennung,
        'project_info_1'      => project_info_1,
        'project_info_2'      => project_info_2,
        'project-info-1'      => project_info_1,
        'project-info-2'      => project_info_2,
        'recipient_name'      => names[:full],
        'recipient_firstname' => names[:first],
        'recipient_lastname'  => names[:last],
        'recipient_email'     => recipient_email.to_s,
        'form_of_address'     => foa,
        'custom_subject'      => custom_subject.to_s,
        'comment'             => comment.to_s,
        'quote'               => '',
        'date'                => I18n.l(Date.today)
      }
      vars['salutation'] = render(settings["salutation_#{foa}"].to_s, vars).strip
      vars['closing']    = render(settings["closing_#{foa}"].to_s, vars).strip
      vars
    end

    # Renders the body template and additionally returns the parts before and
    # after `{comment}` so the UI can show header/footer around the comment.
    # Returns { body:, header:, footer:, comment: }.
    def render_body_parts(template, vars)
      tpl = template.to_s
      body = render(tpl, vars)
      if tpl.include?('{comment}')
        before, after = tpl.split('{comment}', 2)
        { body: body,
          header: render(before, vars),
          footer: render(after.to_s, vars),
          comment: vars['comment'].to_s }
      else
        { body: body, header: body, footer: '', comment: vars['comment'].to_s }
      end
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
