require_dependency 'user_preference'

# Stores the per-user default form of address (Du/Sie) for outgoing mails in
# the user's preferences (`others` hash). Editable under "My account" and in
# the admin user form via the plugin's view hooks.
module RedmineSendmail
  module UserPreferencePatch
    extend ActiveSupport::Concern

    included do
      safe_attributes 'sendmail_form_of_address'
    end

    def sendmail_form_of_address
      self[:sendmail_form_of_address]
    end

    def sendmail_form_of_address=(value)
      v = value.to_s.strip.downcase
      self[:sendmail_form_of_address] = %w[du sie].include?(v) ? v : nil
    end
  end
end

unless UserPreference.included_modules.include?(RedmineSendmail::UserPreferencePatch)
  UserPreference.include(RedmineSendmail::UserPreferencePatch)
end
