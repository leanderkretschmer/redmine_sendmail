require_dependency 'journal'

module RedmineSendmail
  module JournalPatch
    extend ActiveSupport::Concern

    included do
      before_destroy :remove_redmine_sendmail_dispatches
    end

    def remove_redmine_sendmail_dispatches
      return unless defined?(RedmineSendmailDispatch)
      RedmineSendmailDispatch.where(journal_id: id).delete_all
    rescue => e
      Rails.logger.warn("[redmine_sendmail] failed to remove dispatches for journal ##{id}: #{e.class}: #{e.message}")
    end
  end
end

unless Journal.included_modules.include?(RedmineSendmail::JournalPatch)
  Journal.include(RedmineSendmail::JournalPatch)
end
