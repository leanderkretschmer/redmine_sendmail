class AddOverridesToRedmineSendmailProjectSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :redmine_sendmail_project_settings, :body_template,         :text
    add_column :redmine_sendmail_project_settings, :subject_template,      :string
    add_column :redmine_sendmail_project_settings, :from_email,            :string
    add_column :redmine_sendmail_project_settings, :from_name,             :string
    add_column :redmine_sendmail_project_settings, :reply_to_email,        :string

    add_column :redmine_sendmail_project_settings, :use_custom_smtp,       :boolean, default: false, null: false
    add_column :redmine_sendmail_project_settings, :smtp_use_mail_handler, :boolean, default: false, null: false
    add_column :redmine_sendmail_project_settings, :smtp_host,             :string
    add_column :redmine_sendmail_project_settings, :smtp_port,             :integer
    add_column :redmine_sendmail_project_settings, :smtp_ssl,              :boolean, default: false, null: false
    add_column :redmine_sendmail_project_settings, :smtp_starttls,         :boolean, default: true,  null: false
    add_column :redmine_sendmail_project_settings, :smtp_authentication,   :string
    add_column :redmine_sendmail_project_settings, :smtp_username,         :string
    add_column :redmine_sendmail_project_settings, :smtp_password,         :string
    add_column :redmine_sendmail_project_settings, :smtp_domain,           :string
  end
end
