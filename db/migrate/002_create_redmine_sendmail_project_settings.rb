class CreateRedmineSendmailProjectSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :redmine_sendmail_project_settings do |t|
      t.references :project, type: :integer, null: false,
                            foreign_key: { on_delete: :cascade },
                            index: { unique: true }
      t.text :info_1
      t.text :info_2
      t.timestamps
    end
  end
end
