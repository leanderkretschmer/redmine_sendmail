class RedmineSendmailDispatchJob < ActiveJob::Base
  queue_as :default

  def perform(journal_id:, params:, attachment_params: nil)
    journal = Journal.find_by(id: journal_id)
    unless journal
      Rails.logger.warn("[redmine_sendmail] dispatch job: journal ##{journal_id} not found — skipping")
      return
    end

    sym_params = params.is_a?(Hash) ? params.symbolize_keys : {}
    Rails.logger.info("[redmine_sendmail] dispatch job: starting for journal ##{journal.id}")
    RedmineSendmail::Dispatcher.dispatch_for_journal(
      journal:           journal,
      params:            sym_params,
      attachment_params: attachment_params
    )
  rescue => e
    Rails.logger.error("[redmine_sendmail] dispatch job failed: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}")
    raise
  end
end
