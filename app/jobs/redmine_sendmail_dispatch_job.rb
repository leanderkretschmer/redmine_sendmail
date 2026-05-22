class RedmineSendmailDispatchJob < ActiveJob::Base
  queue_as :default

  def perform(params:, journal_id: nil, issue_id: nil, attachment_params: nil)
    sym_params = params.is_a?(Hash) ? params.symbolize_keys : {}

    if journal_id
      journal = Journal.find_by(id: journal_id)
      unless journal
        Rails.logger.warn("[redmine_sendmail] dispatch job: journal ##{journal_id} not found — skipping")
        return
      end
      Rails.logger.info("[redmine_sendmail] dispatch job: starting for journal ##{journal.id}")
      RedmineSendmail::Dispatcher.dispatch_for_journal(
        journal:           journal,
        params:            sym_params,
        attachment_params: attachment_params
      )
    elsif issue_id
      issue = Issue.find_by(id: issue_id)
      unless issue
        Rails.logger.warn("[redmine_sendmail] dispatch job: issue ##{issue_id} not found — skipping")
        return
      end
      Rails.logger.info("[redmine_sendmail] dispatch job: starting for new issue ##{issue.id}")
      RedmineSendmail::Dispatcher.dispatch_for_issue(
        issue:             issue,
        params:            sym_params,
        attachment_params: attachment_params
      )
    else
      Rails.logger.warn('[redmine_sendmail] dispatch job: neither journal_id nor issue_id given — skipping')
    end
  rescue => e
    Rails.logger.error("[redmine_sendmail] dispatch job failed: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}")
    raise
  end
end
