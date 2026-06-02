require 'redmine'

Rails.application.config.to_prepare do
  require_dependency File.expand_path('lib/redmine_sendmail/view_hook', __dir__)
  require_dependency File.expand_path('lib/redmine_sendmail/controller_hook', __dir__)
  require_dependency File.expand_path('lib/redmine_sendmail/projects_helper_patch', __dir__)
  require_dependency File.expand_path('lib/redmine_sendmail/journal_patch', __dir__)
  require_dependency File.expand_path('app/jobs/redmine_sendmail_dispatch_job', __dir__)
end

Redmine::Plugin.register :redmine_sendmail do
  name 'Redmine Sendmail'
  author 'Leander Kretschmer'
  description 'Sendet Ticket-Kommentare als E-Mail an einen Kontakt aus der Redmine-CRM-Kontaktliste des Projekts.'
  version '0.1.0'
  url 'https://github.com/leanderkretschmer/redmine_sendmail'
  author_url 'https://github.com/leanderkretschmer'

  requires_redmine version_or_higher: '6.0.0'

  settings(
    default: {
      'subject_template' => '[#{ticket_id}] {custom_subject}',
      'body_template' => "Hallo {recipient_name},\n\n{comment}\n\n--\n{user_name}\n{user_email}\n\n(Ticket: {ticket_url})\n",
      'from_email' => '',
      'from_name' => '',
      'reply_to_email' => '',
      'use_project_alias' => '0',
      'project_identifier_slice' => '',
      'log_dispatches' => '1',
      'use_custom_smtp' => '0',
      'smtp_use_mail_handler' => '0',
      'smtp_host' => '',
      'smtp_port' => '587',
      'smtp_ssl' => '0',
      'smtp_starttls' => '1',
      'smtp_username' => '',
      'smtp_password' => '',
      'smtp_authentication' => 'plain',
      'smtp_domain' => ''
    },
    partial: 'settings/redmine_sendmail'
  )

  project_module :sendmail do
    permission :send_sendmail,
               { redmine_sendmail_dispatches: [:index, :show, :preview] },
               require: :member
  end

  menu :project_menu,
       :sendmail,
       { controller: 'redmine_sendmail_dispatches', action: 'index' },
       caption: :label_sendmail,
       after: :issues,
       param: :project_id,
       if: Proc.new { |p| p.module_enabled?(:sendmail) }
end
