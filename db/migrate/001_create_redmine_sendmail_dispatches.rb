class CreateRedmineSendmailDispatches < ActiveRecord::Migration[7.0]
  def change
    create_table :redmine_sendmail_dispatches do |t|
      t.references :issue,   type: :integer, null: false,
                             foreign_key: { on_delete: :cascade }, index: true
      t.references :journal, type: :integer, null: true,
                             foreign_key: { on_delete: :nullify }, index: true
      t.references :project, type: :integer, null: false,
                             foreign_key: { on_delete: :cascade }, index: true
      t.references :user,    type: :integer, null: false,
                             foreign_key: { on_delete: :restrict }, index: true
      t.integer :contact_id, null: true, index: true
      t.string  :recipient_email, null: false, limit: 320
      t.string  :recipient_name,  limit: 255
      t.string  :subject,         null: false, limit: 998
      t.text    :body
      t.string  :status, null: false, default: 'sent', limit: 16
      t.text    :error_message
      t.timestamps
    end
  end
end
