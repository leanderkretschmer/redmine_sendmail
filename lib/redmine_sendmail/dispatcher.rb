require_dependency File.expand_path('template_renderer', __dir__)
require_dependency File.expand_path('smtp_resolver', __dir__)

module RedmineSendmail
  module Dispatcher
    module_function

    def dispatch_for_journal(journal:, params:)
      return [] if params.blank?
      return [] unless journal && journal.notes.present?

      contact_ids = extract_contact_ids(params)
      if contact_ids.empty?
        Rails.logger.info("[redmine_sendmail] dispatcher: no contacts selected for journal ##{journal.id}")
        return []
      end

      custom_subject = params[:subject].to_s.strip
      issue          = journal.journalized
      project        = issue.project
      user           = journal.user || User.current

      settings    = Setting.plugin_redmine_sendmail || {}
      smtp_config = SmtpResolver.resolve(settings)
      Rails.logger.info("[redmine_sendmail] dispatcher: SMTP config = #{smtp_config ? smtp_config.except(:password).inspect : 'default ActionMailer'}; #{contact_ids.size} recipient(s)")

      contact_ids.map do |cid|
        dispatch_one(
          issue:          issue,
          project:        project,
          journal:        journal,
          user:           user,
          contact_id:     cid,
          custom_subject: custom_subject,
          settings:       settings,
          smtp_config:    smtp_config
        )
      end.compact
    end

    def extract_contact_ids(params)
      ids = params[:contact_ids]
      ids = ids.values if ids.is_a?(Hash)
      ids = Array(ids).flatten
      if ids.empty? && params[:contact_id].to_s.strip.present?
        ids = [params[:contact_id]]
      end
      ids.map { |v| v.to_s.strip }.reject(&:blank?).uniq
    end

    def dispatch_one(issue:, project:, journal:, user:, contact_id:, custom_subject:, settings:, smtp_config:)
      contact = lookup_contact(contact_id, project, user)
      unless contact
        Rails.logger.warn("[redmine_sendmail] contact ##{contact_id} not found / not visible — skipping")
        return nil
      end
      recipient_email = contact.primary_email.to_s.strip
      if recipient_email.blank?
        Rails.logger.warn("[redmine_sendmail] contact ##{contact_id} (#{contact.name}) has no e-mail — skipping")
        return nil
      end
      recipient_name = contact.name

      vars = TemplateRenderer.build_vars(
        user:            user,
        issue:           issue,
        contact:         contact,
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        custom_subject:  custom_subject,
        comment:         journal.notes
      )

      subject_template = settings['subject_template'].presence || '[#{ticket_id}] {custom_subject}'
      body_template    = settings['body_template'].to_s
      subject = TemplateRenderer.render(subject_template, vars).strip
      subject = "[##{issue.id}]" if subject.blank?
      body    = TemplateRenderer.render(body_template, vars)

      from_email = resolve_from(settings)
      reply_to   = resolve_reply_to(settings)

      record = RedmineSendmailDispatch.new(
        issue_id:        issue.id,
        journal_id:      journal.id,
        project_id:      project.id,
        user_id:         user.id,
        contact_id:      contact.id,
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        subject:         subject.first(998),
        body:            body,
        status:          'sent'
      )

      Rails.logger.info("[redmine_sendmail] dispatcher: sending to #{recipient_email} (issue ##{issue.id}, journal ##{journal.id}, contact ##{contact.id}, from=#{from_email.inspect}, reply_to=#{reply_to.inspect})")
      begin
        delivered = RedmineSendmailMailer.dispatch(
          subject:         subject,
          body:            body,
          recipient_email: recipient_email,
          recipient_name:  recipient_name,
          from_email:      from_email,
          reply_to:        reply_to,
          extra_headers:   { 'X-Redmine-Issue' => issue.id.to_s, 'X-Redmine-Project' => project.identifier.to_s },
          smtp_config:     smtp_config
        ).deliver_now
        Rails.logger.info("[redmine_sendmail] dispatcher: deliver_now OK (message_id=#{delivered&.message_id.inspect}, body_size=#{body.to_s.bytesize})")
      rescue => e
        record.status = 'failed'
        record.error_message = "#{e.class}: #{e.message}"
        Rails.logger.error("[redmine_sendmail] delivery failed for #{recipient_email}: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}")
      end

      record.save if settings['log_dispatches'].to_s == '1' || record.status == 'failed'
      record
    end

    def resolve_from(settings)
      explicit = settings['from_email'].to_s.strip
      return explicit if explicit.present?
      mh = SmtpResolver.mail_handler_account_email
      return mh if mh
      fallback = (Setting.mail_from rescue nil).to_s.strip
      fallback.presence
    end

    def resolve_reply_to(settings)
      explicit = settings['reply_to_email'].to_s.strip
      return explicit if explicit.present?
      SmtpResolver.mail_handler_account_email
    end

    def lookup_contact(contact_id, project, user)
      return nil if contact_id.blank?
      return nil unless defined?(Contact)
      scope = Contact.where(id: contact_id)
      scope = scope.by_project(project.id) if Contact.respond_to?(:by_project)
      scope = scope.visible(user)          if Contact.respond_to?(:visible)
      scope.first
    end
  end
end
