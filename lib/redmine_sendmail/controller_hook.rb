require_dependency File.expand_path('dispatcher', __dir__)

module RedmineSendmail
  class ControllerHook < Redmine::Hook::Listener
    def controller_issues_edit_after_save(context = {})
      issue   = context[:issue]
      journal = context[:journal]
      params  = context[:params]
      Rails.logger.info("[redmine_sendmail] after_save hook fired (issue=#{issue&.id}, journal=#{journal&.id}, params_keys=#{params&.keys&.inspect})")
      unless issue && journal && params
        Rails.logger.info("[redmine_sendmail] after_save: skip (missing issue/journal/params)")
        return
      end
      sm = params[:sendmail]
      if sm.blank?
        Rails.logger.info("[redmine_sendmail] after_save: skip (no sendmail params submitted)")
        return
      end
      project = issue.project
      unless project.module_enabled?(:sendmail)
        Rails.logger.info("[redmine_sendmail] after_save: skip (module not enabled on project ##{project.id})")
        return
      end
      unless User.current.allowed_to?(:send_sendmail, project)
        Rails.logger.info("[redmine_sendmail] after_save: skip (user #{User.current.login} lacks :send_sendmail)")
        return
      end
      sm_hash = sm.respond_to?(:to_unsafe_h) ? sm.to_unsafe_h : sm.to_h
      Rails.logger.info("[redmine_sendmail] after_save: dispatching for journal ##{journal.id}, params=#{sm_hash.inspect}")
      RedmineSendmail::Dispatcher.dispatch_for_journal(journal: journal, params: sm_hash.symbolize_keys)
    rescue => e
      Rails.logger.error("[redmine_sendmail] dispatch hook failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end
end
