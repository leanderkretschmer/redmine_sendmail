require_dependency File.expand_path('reply_helper', __dir__)

module RedmineSendmail
  class ViewHook < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller
      is_issues = controller.is_a?(IssuesController)
      is_dispatches = defined?(RedmineSendmailDispatchesController) &&
                      controller.is_a?(RedmineSendmailDispatchesController)
      is_contacts = defined?(ContactsController) && controller.is_a?(ContactsController)
      return '' unless is_issues || is_dispatches || is_contacts
      out = [stylesheet_link_tag('redmine_sendmail', plugin: 'redmine_sendmail')]
      out << javascript_include_tag('redmine_sendmail', plugin: 'redmine_sendmail') if is_issues
      safe_join(out, "\n")
    end

    def view_issues_edit_notes_bottom(context = {})
      issue = context[:issue]
      project = context[:project] || issue&.project
      unless project && issue
        Rails.logger.info("[redmine_sendmail] view_hook: skip (no issue/project)")
        return ''
      end
      unless project.module_enabled?(:sendmail)
        Rails.logger.info("[redmine_sendmail] view_hook: skip (module 'sendmail' not enabled on project ##{project.id} #{project.identifier})")
        return ''
      end
      unless User.current.allowed_to?(:send_sendmail, project)
        Rails.logger.info("[redmine_sendmail] view_hook: skip (user #{User.current.login} lacks :send_sendmail on project ##{project.id})")
        return ''
      end

      controller = context[:controller]
      contacts   = load_contacts(project, User.current)
      Rails.logger.info("[redmine_sendmail] view_hook: rendering form for issue ##{issue.id}, #{contacts.size} contact(s)")
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/issue_notes_form',
                      locals:  { issue: issue, project: project, contacts: contacts,
                                 options: form_options(project) })
    end

    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      return '' unless issue && issue.new_record?
      project = issue.project || context[:project]
      unless project
        Rails.logger.info('[redmine_sendmail] new-issue view_hook: skip (no project yet)')
        return ''
      end
      unless project.module_enabled?(:sendmail)
        Rails.logger.info("[redmine_sendmail] new-issue view_hook: skip (module 'sendmail' not enabled on project ##{project.id})")
        return ''
      end
      unless User.current.allowed_to?(:send_sendmail, project)
        Rails.logger.info("[redmine_sendmail] new-issue view_hook: skip (user #{User.current.login} lacks :send_sendmail)")
        return ''
      end

      controller = context[:controller]
      contacts   = load_contacts(project, User.current)
      Rails.logger.info("[redmine_sendmail] new-issue view_hook: rendering form for project ##{project.id}, #{contacts.size} contact(s)")
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/issue_new_form',
                      locals:  { issue: issue, project: project, contacts: contacts,
                                 options: form_options(project) })
    end

    def view_issues_history_journal_bottom(context = {})
      journal = context[:journal]
      return '' unless journal && journal.id
      controller = context[:controller]
      out = []
      dispatches = RedmineSendmailDispatch.where(journal_id: journal.id).order(:created_at).to_a
      if dispatches.any?
        out << controller.send(:render_to_string,
                               partial: 'redmine_sendmail/journal_sent_marker',
                               locals:  { dispatches: dispatches })
      end
      reply = reply_link_html(journal, controller)
      out << reply if reply.present?
      safe_join(out, "\n")
    end

    # "Reply by e-mail" link under every comment: carries the preselected
    # recipients, the computed subject and the origin of the comment so the
    # JS can fill the notes form like a mail client's reply button.
    def reply_link_html(journal, controller)
      return '' unless journal.notes.present? && journal.journalized_type == 'Issue'
      issue   = journal.journalized
      project = issue&.project
      return '' unless issue && project
      return '' unless project.module_enabled?(:sendmail)
      return '' unless User.current.allowed_to?(:send_sendmail, project)
      return '' unless issue.notes_addable?
      # Only comments that arrived by e-mail get a reply button — replying
      # by mail to a comment written in Redmine or posted via API is wrong.
      return '' unless ReplyHelper.email_origin?(journal)
      recipients = ReplyHelper.reply_recipients(journal, project, User.current)
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/journal_reply_link',
                      locals:  { journal:    journal,
                                 issue:      issue,
                                 origin:     ReplyHelper.journal_origin(journal),
                                 subject:    ReplyHelper.reply_subject(issue, journal),
                                 recipients: recipients })
    rescue => e
      Rails.logger.warn("[redmine_sendmail] reply link failed for journal ##{journal.id}: #{e.class}: #{e.message}")
      ''
    end

    # Per-user default form of address (Du/Sie) — "My account" page.
    def view_my_account_preferences(context = {})
      render_user_preferences(context)
    end

    # Same field in the admin user form.
    def view_users_form_preferences(context = {})
      render_user_preferences(context)
    end

    def render_user_preferences(context)
      user = context[:user]
      controller = context[:controller]
      return '' unless user && controller
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/user_preferences',
                      locals:  { user: user })
    rescue => e
      Rails.logger.warn("[redmine_sendmail] user preferences hook failed: #{e.class}: #{e.message}")
      ''
    end

    def view_issues_show_description_bottom(context = {})
      issue = context[:issue]
      return '' unless issue && issue.id
      dispatches = RedmineSendmailDispatch.where(issue_id: issue.id, journal_id: nil)
                                          .order(:created_at).to_a
      return '' if dispatches.empty?
      controller = context[:controller]
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/journal_sent_marker',
                      locals:  { dispatches: dispatches })
    end

    def view_contacts_show_details_bottom(context = {})
      contact = context[:contact]
      return '' unless contact
      return '' unless User.current.admin?
      controller = context[:controller]
      projects = Array(contact.projects).select { |p| p.module_enabled?(:sendmail) }
      return '' if projects.empty?
      kennungen = {}
      RedmineSendmailContactProjectKennung
        .where(contact_id: contact.id, project_id: projects.map(&:id))
        .each { |k| kennungen[k.project_id] = k.value.to_s }
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/contact_kennungen',
                      locals:  { contact: contact, projects: projects, kennungen: kennungen })
    rescue => e
      Rails.logger.warn("[redmine_sendmail] view_contacts hook failed: #{e.class}: #{e.message}")
      ''
    end

    private

    # Defaults for the per-mail option controls (form of address, quote).
    def form_options(project)
      settings = RedmineSendmailProjectSetting.effective_settings(project, Setting.plugin_redmine_sendmail || {})
      {
        form_of_address: ReplyHelper.form_of_address_for(User.current, settings),
        quote_default:   settings['quote_default'].to_s != '0'
      }
    rescue => e
      Rails.logger.warn("[redmine_sendmail] form_options failed: #{e.class}: #{e.message}")
      { form_of_address: 'sie', quote_default: true }
    end

    def load_contacts(project, user)
      return [] unless defined?(Contact)
      scope = Contact.all
      scope = scope.by_project(project.id) if Contact.respond_to?(:by_project)
      scope = scope.visible(user)          if Contact.respond_to?(:visible)
      scope = scope.where("#{Contact.table_name}.email IS NOT NULL AND #{Contact.table_name}.email <> ''")
      scope = scope.order("#{Contact.table_name}.last_name, #{Contact.table_name}.first_name")
      scope.to_a
    rescue => e
      Rails.logger.warn("[redmine_sendmail] failed to load contacts: #{e.class}: #{e.message}")
      []
    end
  end
end
