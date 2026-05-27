class RedmineSendmailProjectSetting < ApplicationRecord
  self.table_name = 'redmine_sendmail_project_settings'

  # Keys whose project-level value (when present) overrides the global plugin
  # setting of the same name in TemplateRenderer / dispatcher.
  TEMPLATE_OVERRIDES = %w[
    body_template subject_template
    from_email from_name reply_to_email
  ].freeze

  belongs_to :project

  validates :project_id, presence: true, uniqueness: true

  def self.values_for(project)
    return ['', ''] unless project
    rec = for_project(project)
    [rec&.info_1.to_s, rec&.info_2.to_s]
  end

  def self.for_project(project)
    return nil unless project
    pid = project.respond_to?(:id) ? project.id : project.to_i
    find_by(project_id: pid)
  rescue => e
    Rails.logger.warn("[redmine_sendmail] project setting lookup failed: #{e.class}: #{e.message}")
    nil
  end

  # Returns the effective plugin-settings hash for the given project:
  # the global settings, with any non-blank project-level template / sender
  # overrides taking precedence. Always returns a fresh hash.
  def self.effective_settings(project, global_settings = nil)
    global_settings ||= Setting.plugin_redmine_sendmail || {}
    rec = for_project(project)
    merged = global_settings.to_h.dup
    return merged unless rec
    TEMPLATE_OVERRIDES.each do |key|
      val = rec.public_send(key)
      merged[key] = val if val.to_s.present?
    end
    merged
  end

  # Builds an SMTP-config hash compatible with ActionMailer's :smtp delivery
  # method, or nil if the project has no usable SMTP override configured —
  # in which case the dispatcher falls back to the global SMTP resolution.
  def smtp_config_hash
    return nil unless use_custom_smtp || smtp_use_mail_handler

    if smtp_use_mail_handler
      cfg = RedmineSendmail::SmtpResolver.mail_handler_smtp
      return cfg if cfg
      Rails.logger.warn("[redmine_sendmail] project ##{project_id}: smtp_use_mail_handler set but redmine_mail_handler settings not usable")
    end

    return nil unless use_custom_smtp
    host = smtp_host.to_s.strip
    if host.blank?
      Rails.logger.warn("[redmine_sendmail] project ##{project_id}: use_custom_smtp set but smtp_host is blank")
      return nil
    end

    RedmineSendmail::SmtpResolver.build(
      host:           host,
      port:           smtp_port,
      username:       smtp_username,
      password:       smtp_password,
      authentication: smtp_authentication,
      domain:         smtp_domain,
      ssl:            smtp_ssl,
      starttls:       smtp_starttls
    )
  end
end
