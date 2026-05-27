require_dependency 'projects_helper'

module RedmineSendmail
  module ProjectsHelperPatch
    # Admin-only "Mail dispatch" project-settings tab. Visibility: project
    # module enabled + Redmine system administrator. Non-admins never see (or
    # can submit) it; the controller enforces the same gate via require_admin
    # on update_project_settings.
    #
    # Note: the prepend at the bottom of this file is the mechanism that makes
    # `super` reach Redmine's own ProjectsHelper#project_settings_tabs. Doing
    # the prepend inside `to_prepare` proved unreliable in this Rails version
    # (the autoloader had not loaded ProjectsHelper yet, so the call was a
    # silent no-op). Mirroring the pattern used by redmine_work_time.
    def project_settings_tabs
      tabs = super
      if @project&.module_enabled?(:sendmail) && User.current.admin?
        tabs << {
          name:    'sendmail',
          action:  :sendmail_settings,
          partial: 'projects/settings/redmine_sendmail',
          label:   :label_sendmail
        }
      end
      tabs
    end
  end
end

unless ProjectsHelper.ancestors.include?(RedmineSendmail::ProjectsHelperPatch)
  ProjectsHelper.prepend(RedmineSendmail::ProjectsHelperPatch)
end
