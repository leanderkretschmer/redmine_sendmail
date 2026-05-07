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
      att_param = params[:attachments]
      att_hash = if att_param.respond_to?(:to_unsafe_h)
                   att_param.to_unsafe_h
                 elsif att_param.respond_to?(:to_h)
                   att_param.to_h
                 else
                   att_param
                 end
      Rails.logger.info("[redmine_sendmail] after_save: enqueueing dispatch for journal ##{journal.id}, params=#{sm_hash.inspect}, attachments=#{att_hash.is_a?(Hash) ? att_hash.keys.inspect : 'none'}")
      RedmineSendmailDispatchJob.perform_later(
        journal_id:        journal.id,
        params:            sm_hash.deep_stringify_keys,
        attachment_params: att_hash.is_a?(Hash) ? att_hash.deep_stringify_keys : nil
      )
    rescue => e
      Rails.logger.error("[redmine_sendmail] dispatch hook failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end
end
