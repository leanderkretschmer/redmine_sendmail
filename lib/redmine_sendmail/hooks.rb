require_dependency File.expand_path('dispatcher', __dir__)

module RedmineSendmail
  class ViewHook < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller
      is_issues = controller.is_a?(IssuesController)
      is_dispatches = defined?(RedmineSendmailDispatchesController) &&
                      controller.is_a?(RedmineSendmailDispatchesController)
      return '' unless is_issues || is_dispatches
      out = [stylesheet_link_tag('redmine_sendmail', plugin: 'redmine_sendmail')]
      out << javascript_include_tag('redmine_sendmail', plugin: 'redmine_sendmail') if is_issues
      safe_join(out, "\n")
    end

    def view_issues_edit_notes_bottom(context = {})
      issue = context[:issue]
      project = context[:project] || issue&.project
      return '' unless project && issue
      return '' unless project.module_enabled?(:sendmail)
      return '' unless User.current.allowed_to?(:send_sendmail, project)

      controller = context[:controller]
      contacts   = load_contacts(project, User.current)
      controller.send(:render_to_string,
                      partial: 'redmine_sendmail/issue_notes_form',
                      locals:  { issue: issue, project: project, contacts: contacts })
    end

    def view_issues_form_details_bottom(context = {})
      # Fallback hook in case the notes hook is not rendered (e.g., new issue with note).
      ''
    end

    private

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

  class ControllerHook < Redmine::Hook::Listener
    def controller_issues_edit_after_save(context = {})
      issue   = context[:issue]
      journal = context[:journal]
      params  = context[:params]
      return unless issue && journal && params
      sm = params[:sendmail]
      return if sm.blank?
      project = issue.project
      return unless project.module_enabled?(:sendmail)
      return unless User.current.allowed_to?(:send_sendmail, project)
      sm_hash = sm.respond_to?(:to_unsafe_h) ? sm.to_unsafe_h : sm.to_h
      RedmineSendmail::Dispatcher.dispatch_for_journal(journal: journal, params: sm_hash.symbolize_keys)
    rescue => e
      Rails.logger.error("[redmine_sendmail] dispatch hook failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end
end
