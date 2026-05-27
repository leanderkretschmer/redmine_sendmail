class AddFailureReasonDetailToRedmineSendmailDispatches < ActiveRecord::Migration[7.0]
  def change
    add_column :redmine_sendmail_dispatches, :failure_reason_detail, :string
  end
end
