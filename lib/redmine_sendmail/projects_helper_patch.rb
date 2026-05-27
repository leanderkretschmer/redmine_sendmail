module RedmineSendmail
  module ProjectsHelperPatch
    # Adds an admin-only "Mail dispatch" tab to a project's settings.
    # Visibility: project module enabled + Redmine system administrator.
    # Non-admins never see (or can submit) it; the controller enforces the
    # same gate via require_admin on update_project_settings.
    def project_settings_tabs
      tabs = super
      if @project&.module_enabled?(:sendmail) && User.current.admin?
        tabs << {
          name:    'redmine_sendmail',
          action:  :manage_sendmail_settings,
          partial: 'projects/settings/redmine_sendmail',
          label:   :label_sendmail
        }
      end
      tabs
    end
  end
end
