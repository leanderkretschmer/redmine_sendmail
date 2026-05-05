module RedmineSendmail
  module SmtpResolver
    module_function

    def mail_handler_account_email
      mh = (Setting.plugin_redmine_mail_handler rescue nil)
      return nil if mh.blank?
      use_imap = mh['smtp_same_as_imap'].to_s == '1' && mh['smtp_host'].to_s.strip.empty?
      candidate = use_imap ? mh['imap_username'] : mh['smtp_username']
      candidate = candidate.to_s.strip
      candidate.match?(/\A[^@\s]+@[^@\s]+\z/) ? candidate : nil
    end

    def resolve(settings = nil)
      settings ||= Setting.plugin_redmine_sendmail || {}
      if settings['smtp_use_mail_handler'].to_s == '1'
        cfg = mail_handler_smtp
        return cfg if cfg
        Rails.logger.warn('[redmine_sendmail] smtp_use_mail_handler enabled but redmine_mail_handler settings not usable; falling back')
      end
      return custom_smtp(settings) if settings['use_custom_smtp'].to_s == '1'
      nil
    end

    def custom_smtp(s)
      host = s['smtp_host'].to_s.strip
      return nil if host.blank?
      build(
        host:           host,
        port:           s['smtp_port'],
        username:       s['smtp_username'],
        password:       s['smtp_password'],
        authentication: s['smtp_authentication'],
        domain:         s['smtp_domain'],
        ssl:            s['smtp_ssl'].to_s == '1',
        starttls:       s['smtp_starttls'].to_s == '1'
      )
    end

    def mail_handler_smtp
      mh = (Setting.plugin_redmine_mail_handler rescue nil)
      return nil if mh.blank?
      use_imap = mh['smtp_same_as_imap'].to_s == '1' && mh['smtp_host'].to_s.strip.empty?
      host     = use_imap ? mh['imap_host']     : mh['smtp_host']
      port     = mh['smtp_port'].presence || (use_imap ? '465' : '587')
      username = use_imap ? mh['imap_username'] : mh['smtp_username']
      password = use_imap ? mh['imap_password'] : mh['smtp_password']
      ssl      = (use_imap ? mh['imap_ssl'] : mh['smtp_ssl']).to_s == '1'
      return nil if host.to_s.strip.empty?
      build(
        host:           host,
        port:           port,
        username:       username,
        password:       password,
        authentication: 'plain',
        domain:         nil,
        ssl:            ssl,
        starttls:       !ssl
      )
    end

    def build(host:, port:, username:, password:, authentication:, domain:, ssl:, starttls:)
      cfg = {
        address: host.to_s.strip,
        port:    port.to_i.nonzero? || 587,
        domain:  (domain.presence || 'localhost').to_s
      }
      if username.to_s.strip.present?
        cfg[:user_name]      = username.to_s
        cfg[:password]       = password.to_s
        cfg[:authentication] = (authentication.presence || 'plain').to_sym
      end
      if ssl
        cfg[:ssl] = true
        cfg[:tls] = true
      elsif starttls
        cfg[:enable_starttls_auto] = true
      end
      cfg.freeze
    end
  end
end
