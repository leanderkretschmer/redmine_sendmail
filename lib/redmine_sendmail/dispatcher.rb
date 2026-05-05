require_dependency File.expand_path('template_renderer', __dir__)

module RedmineSendmail
  module Dispatcher
    module_function

    def dispatch_for_journal(journal:, params:)
      return nil if params.blank?
      contact_id = params[:contact_id].to_s.strip
      recipient_email = params[:recipient_email].to_s.strip
      custom_subject  = params[:subject].to_s.strip

      return nil if contact_id.blank? && recipient_email.blank?
      return nil unless journal && journal.notes.present?

      issue   = journal.journalized
      project = issue.project
      user    = journal.user || User.current

      contact = lookup_contact(contact_id, project, user)
      if contact && recipient_email.blank?
        recipient_email = contact.primary_email.to_s.strip
      end
      recipient_name = contact ? contact.name : nil

      if recipient_email.blank?
        Rails.logger.warn("[redmine_sendmail] Skipping dispatch for journal #{journal.id}: no recipient email")
        return nil
      end

      settings = Setting.plugin_redmine_sendmail || {}
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

      from_email = settings['from_email'].presence
      reply_to   = (settings['reply_to_user'].to_s == '1' && user.mail.present?) ? user.mail : nil

      record = RedmineSendmailDispatch.new(
        issue_id:        issue.id,
        journal_id:      journal.id,
        project_id:      project.id,
        user_id:         user.id,
        contact_id:      contact&.id,
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        subject:         subject.first(998),
        body:            body,
        status:          'sent'
      )

      begin
        RedmineSendmailMailer.dispatch(
          subject:         subject,
          body:            body,
          recipient_email: recipient_email,
          recipient_name:  recipient_name,
          from_email:      from_email,
          reply_to:        reply_to,
          extra_headers:   { 'X-Redmine-Issue' => issue.id.to_s, 'X-Redmine-Project' => project.identifier.to_s }
        ).deliver_now
      rescue => e
        record.status = 'failed'
        record.error_message = "#{e.class}: #{e.message}"
        Rails.logger.error("[redmine_sendmail] delivery failed: #{e.class}: #{e.message}")
      end

      record.save if settings['log_dispatches'].to_s == '1' || record.status == 'failed'
      record
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
