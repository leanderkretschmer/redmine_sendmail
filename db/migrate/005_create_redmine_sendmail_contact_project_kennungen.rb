class CreateRedmineSendmailContactProjectKennungen < ActiveRecord::Migration[7.0]
  def change
    create_table :redmine_sendmail_contact_kennungen do |t|
      t.integer :contact_id, null: false
      t.references :project, type: :integer, null: false,
                             foreign_key: { on_delete: :cascade }, index: true
      t.string :value, null: false, limit: 255, default: ''
      t.timestamps
    end
    add_index :redmine_sendmail_contact_kennungen, [:contact_id, :project_id],
              unique: true, name: 'idx_sendmail_kennungen_contact_project'
    add_index :redmine_sendmail_contact_kennungen, :contact_id
  end
end
