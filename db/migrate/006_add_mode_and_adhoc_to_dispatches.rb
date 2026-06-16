class AddModeAndAdhocToDispatches < ActiveRecord::Migration[7.0]
  def change
    add_column :redmine_sendmail_dispatches, :mode, :string, limit: 8,
                                                             default: 'to', null: false
    add_column :redmine_sendmail_dispatches, :is_adhoc, :boolean,
                                                             default: false, null: false
  end
end
