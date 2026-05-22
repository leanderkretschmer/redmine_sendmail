module RedmineSendmail
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:sendmail) &&
         User.current.allowed_to?(:manage_sendmail_settings, @project)
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
