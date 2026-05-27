require 'resolv'

module RedmineSendmail
  # Best-effort classification of why an outgoing mail bounced.
  # Returns a short symbolic code (used as a locale key) or nil when no useful
  # diagnosis is available. The code is stored in
  # RedmineSendmailDispatch#failure_reason_detail and rendered as a tooltip
  # next to the "Fehler" status in the UI.
  #
  # Strategy:
  #   1. Validate the recipient address.
  #   2. DNS-MX lookup on the recipient's domain.
  #   3. Pattern-match the raw SMTP error message for well-known bounces.
  module BounceChecker
    module_function

    PATTERNS = {
      'mailbox_unknown' => [
        /user unknown/i, /no such user/i, /unknown user/i,
        /no such mailbox/i, /mailbox unavailable/i,
        /recipient address rejected/i, /address rejected/i,
        /does not exist/i, /no mailbox here/i, /\b5\.1\.1\b/
      ],
      'mailbox_full' => [
        /mailbox full/i, /over quota/i, /quota exceeded/i, /\b5\.2\.2\b/
      ],
      'auth_failed' => [
        /authentication failed/i, /authentication required/i,
        /\b5\.7\.0\b/, /\b5\.7\.8\b/
      ],
      'rate_limited' => [
        /\b4\.7\.\d\b/, /too many/i, /rate limit/i, /try again later/i
      ],
      'spam_blocked' => [
        /spam/i, /blacklist/i, /reject(ed)?.*spam/i, /\b5\.7\.1\b/, /policy.*reject/i
      ]
    }.freeze

    def analyze(email, error_message)
      email = email.to_s.strip
      return 'invalid_address' if email.empty? || !email.include?('@')
      domain = email.split('@').last.to_s.strip.downcase
      return 'invalid_address' if domain.empty? || !domain.include?('.')

      mx_present, dns_error = check_mx(domain)
      return 'domain_not_resolvable' if dns_error
      return 'domain_no_mx'          unless mx_present

      msg = error_message.to_s
      PATTERNS.each do |code, patterns|
        return code if patterns.any? { |re| re.match?(msg) }
      end

      msg.empty? ? nil : 'smtp_error'
    rescue => e
      Rails.logger.warn("[redmine_sendmail] bounce check error for #{email.inspect}: #{e.class}: #{e.message}")
      nil
    end

    def check_mx(domain)
      records = []
      Resolv::DNS.open do |dns|
        dns.timeouts = 3
        records = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
      end
      [records.any?, nil]
    rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
      Rails.logger.info("[redmine_sendmail] DNS MX lookup failed for #{domain.inspect}: #{e.class}: #{e.message}")
      [false, e]
    rescue => e
      Rails.logger.warn("[redmine_sendmail] DNS MX lookup error for #{domain.inspect}: #{e.class}: #{e.message}")
      [false, e]
    end
  end
end
