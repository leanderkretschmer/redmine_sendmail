class RedmineSendmailProjectSetting < ApplicationRecord
  self.table_name = 'redmine_sendmail_project_settings'

  belongs_to :project

  validates :project_id, presence: true, uniqueness: true

  # Returns the two free-text project values as a [info_1, info_2] string pair,
  # never nil. Used to expose them as mail-template placeholders.
  def self.values_for(project)
    return ['', ''] unless project
    rec = find_by(project_id: project.respond_to?(:id) ? project.id : project.to_i)
    [rec&.info_1.to_s, rec&.info_2.to_s]
  rescue => e
    Rails.logger.warn("[redmine_sendmail] project setting lookup failed: #{e.class}: #{e.message}")
    ['', '']
  end
end
