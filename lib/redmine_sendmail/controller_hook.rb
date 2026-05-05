require_dependency File.expand_path('dispatcher', __dir__)

module RedmineSendmail
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
