class RedmineSendmailDispatch < ApplicationRecord
  self.table_name = 'redmine_sendmail_dispatches'

  belongs_to :issue
  belongs_to :journal, optional: true
  belongs_to :project
  belongs_to :user

  validates :recipient_email, presence: true,
                              format: { with: /\A[^@\s]+@[^@\s]+\z/ }
  validates :subject, presence: true
  validates :status, inclusion: { in: %w[sent failed] }
  validates :mode, inclusion: { in: %w[to cc bcc] }

  scope :for_project, ->(project) { where(project_id: project.id) }
  scope :latest_first, -> { order(created_at: :desc) }

  def contact
    return nil unless contact_id && defined?(Contact)
    @contact ||= Contact.find_by(id: contact_id)
  end

  def sent?
    status == 'sent'
  end
end
