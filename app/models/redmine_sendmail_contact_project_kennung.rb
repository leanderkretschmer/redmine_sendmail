class RedmineSendmailContactProjectKennung < ApplicationRecord
  self.table_name = 'redmine_sendmail_contact_kennungen'

  belongs_to :project
  validates :contact_id, presence: true
  validates :project_id, presence: true
  validates :contact_id, uniqueness: { scope: :project_id }

  def self.value_for(contact_or_id, project_or_id)
    cid = contact_or_id.respond_to?(:id) ? contact_or_id.id : contact_or_id
    pid = project_or_id.respond_to?(:id) ? project_or_id.id : project_or_id
    return '' if cid.blank? || pid.blank?
    where(contact_id: cid, project_id: pid).pick(:value).to_s
  rescue => e
    Rails.logger.warn("[redmine_sendmail] kennung lookup failed (contact=#{cid}, project=#{pid}): #{e.class}: #{e.message}")
    ''
  end

  def self.upsert_value(contact_id:, project_id:, value:)
    rec = find_or_initialize_by(contact_id: contact_id, project_id: project_id)
    rec.value = value.to_s
    if rec.value.strip.empty? && rec.persisted?
      rec.destroy
      nil
    else
      rec.save
      rec
    end
  end
end
