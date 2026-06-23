class AddAttachmentFilenamesToDispatches < ActiveRecord::Migration[7.0]
  def change
    add_column :redmine_sendmail_dispatches, :attachment_filenames, :text
  end
end
