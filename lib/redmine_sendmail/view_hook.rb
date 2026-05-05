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
end
