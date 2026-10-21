# Helpers for the "reply by e-mail" feature: form of address (Du/Sie),
# name formatting (first-name-only / lowercase), reply subject computation,
# origin detection of a journal (did it arrive as e-mail?) and quoting of
# the comment being replied to.
module RedmineSendmail
  module ReplyHelper
    module_function

    FORMS_OF_ADDRESS = %w[du sie].freeze
    RE_PREFIX = /\A\s*(?:re|aw|wg|fw|fwd|antw|sv|vs)\s*:\s*/i

    # ---- form of address -------------------------------------------------

    def normalize_form_of_address(value)
      v = value.to_s.strip.downcase
      FORMS_OF_ADDRESS.include?(v) ? v : nil
    end

    # Effective form of address for `user`: explicit override (form field)
    # → user preference ("Mein Konto") → global plugin default → 'sie'.
    def form_of_address_for(user, settings = nil, override = nil)
      explicit = normalize_form_of_address(override)
      return explicit if explicit
      pref = user_pref_form_of_address(user)
      return pref if pref
      settings ||= Setting.plugin_redmine_sendmail || {}
      normalize_form_of_address(settings['form_of_address_default']) || 'sie'
    end

    def user_pref_form_of_address(user)
      return nil unless user && user.respond_to?(:pref) && !user.anonymous?
      normalize_form_of_address(user.pref[:sendmail_form_of_address])
    rescue => e
      Rails.logger.warn("[redmine_sendmail] user pref lookup failed: #{e.class}: #{e.message}")
      nil
    end

    def truthy?(value)
      %w[1 true on yes].include?(value.to_s.strip.downcase)
    end

    # ---- name formatting -------------------------------------------------

    # Splits a free-text name ("Fritz Müller") into [first, last].
    def split_name(name)
      parts = name.to_s.strip.split(/\s+/)
      return ['', ''] if parts.empty?
      [parts.first, parts[1..].to_a.join(' ')]
    end

    # Returns { full:, first:, last: } for a recipient. Contacts use their
    # structured first/last name; companies only have a (company) name;
    # ad-hoc recipients are split heuristically. `lowercase` forces the
    # whole name to lower case, `first_only` reduces `full` to the first name.
    def recipient_names(contact:, fallback_name:, lowercase: false, first_only: false)
      if contact && contact.respond_to?(:is_company?) && contact.is_company?
        first = contact.name.to_s
        last  = ''
        full  = first
      elsif contact
        first = contact.first_name.to_s.strip
        last  = contact.last_name.to_s.strip
        full  = contact.name.to_s.strip
        full  = [first, last].reject(&:blank?).join(' ') if full.blank?
      else
        first, last = split_name(fallback_name)
        full = fallback_name.to_s.strip
      end
      full = first if first_only && first.present?
      if lowercase
        full  = full.downcase
        first = first.downcase
        last  = last.downcase
      end
      { full: full, first: first, last: last }
    end

    def user_display_name(user, first_only: false)
      return '' unless user
      if first_only && user.respond_to?(:firstname) && user.firstname.to_s.strip.present?
        user.firstname.to_s.strip
      else
        user.name.to_s
      end
    end

    # ---- journal origin / reply subject ---------------------------------

    # Heuristic: redmine_mail_handler creates the sender user with
    # login == e-mail address and status LOCKED, and prepends the mail
    # subject as the first line of the journal notes. A journal whose author
    # matches that convention is treated as "arrived by e-mail".
    def email_origin?(journal)
      return false unless journal && journal.notes.present?
      user = journal.user
      return false unless user && !user.anonymous?
      user.login.to_s.include?('@') || (user.respond_to?(:locked?) && user.locked?)
    rescue => e
      Rails.logger.warn("[redmine_sendmail] email_origin? failed: #{e.class}: #{e.message}")
      false
    end

    def journal_origin(journal)
      email_origin?(journal) ? 'email' : 'other'
    end

    # The original mail subject as written by redmine_mail_handler into the
    # first line of the notes (only meaningful for e-mail origin journals).
    def original_mail_subject(journal)
      return '' unless journal && journal.notes.present?
      first = journal.notes.to_s.lines.first.to_s.strip
      clean_subject(first)
    end

    # Strips reply/forward prefixes and ticket-number tokens like "[#123]".
    def clean_subject(subject)
      s = subject.to_s.dup
      s = s.sub(RE_PREFIX, '') while s =~ RE_PREFIX
      s = s.gsub(/\[#\d+\]/, '')
      s.gsub(/\s{2,}/, ' ').strip
    end

    # "re: <original subject>, <ticket subject> #<id>" for mails that arrived
    # by e-mail, otherwise "<ticket subject> #<id>".
    def reply_subject(issue, journal)
      base = "#{issue.subject.to_s.strip} ##{issue.id}"
      return base unless email_origin?(journal)
      orig = original_mail_subject(journal)
      orig.present? ? "re: #{orig}, #{base}" : base
    end

    # ---- recipient preselection -----------------------------------------

    # Recipients to preselect when replying to `journal`:
    #   1. the recipients the journal itself was sent to (reply to own mail),
    #   2. the project contact whose e-mail matches the journal author,
    #   3. the recipients of the most recent dispatch of the same issue.
    # Returns { contacts: [{id:, mode:}], adhoc: [{email:, name:, mode:}] }.
    def reply_recipients(journal, project, user)
      issue = journal.journalized
      from_dispatches = dispatch_recipients(RedmineSendmailDispatch.where(journal_id: journal.id), project, user)
      return from_dispatches if from_dispatches[:contacts].any? || from_dispatches[:adhoc].any?

      contact = contact_for_user(journal.user, project, user)
      return { contacts: [{ id: contact.id, mode: 'to' }], adhoc: [] } if contact

      # Sender of an incoming mail who is not (yet) a project contact:
      # preselect the real address as ad-hoc recipient.
      if email_origin?(journal)
        addr = sender_address(journal.user)
        return { contacts: [], adhoc: [{ email: addr, name: sender_name(journal.user), mode: 'to' }] } if addr
      end

      last = RedmineSendmailDispatch.where(issue_id: issue.id).order(created_at: :desc).first
      return { contacts: [], adhoc: [] } unless last
      siblings = RedmineSendmailDispatch.where(issue_id: issue.id, journal_id: last.journal_id)
                                        .where('created_at >= ?', last.created_at - 60)
      dispatch_recipients(siblings, project, user)
    rescue => e
      Rails.logger.warn("[redmine_sendmail] reply_recipients failed: #{e.class}: #{e.message}")
      { contacts: [], adhoc: [] }
    end

    def dispatch_recipients(scope, project, user)
      contacts = []
      adhoc    = []
      seen     = {}
      scope.order(:created_at).each do |d|
        key = d.recipient_email.to_s.downcase
        next if key.blank? || seen[key]
        seen[key] = true
        mode = %w[to cc bcc].include?(d.mode.to_s) ? d.mode.to_s : 'to'
        if d.contact_id && Dispatcher.lookup_contact(d.contact_id, project, user)
          contacts << { id: d.contact_id, mode: mode }
        else
          adhoc << { email: d.recipient_email.to_s, name: d.recipient_name.to_s, mode: mode }
        end
      end
      { contacts: contacts, adhoc: adhoc }
    end

    # All known addresses of a user, lower-cased, without the placeholder
    # ("dummy") addresses redmine_mail_handler assigns to created senders.
    def user_addresses(journal_user)
      return [] unless journal_user && !journal_user.anonymous?
      addresses = []
      addresses << journal_user.mail.to_s if journal_user.respond_to?(:mail)
      if journal_user.respond_to?(:email_addresses)
        addresses.concat(journal_user.email_addresses.map(&:address))
      end
      addresses = addresses.map { |a| a.to_s.strip.downcase }.reject(&:blank?).uniq
      suffix = dummy_mail_suffix
      real = suffix ? addresses.reject { |a| a.end_with?("@#{suffix}") } : addresses
      real.any? ? real : addresses
    rescue => e
      Rails.logger.warn("[redmine_sendmail] user_addresses failed: #{e.class}: #{e.message}")
      []
    end

    def dummy_mail_suffix
      mh = Setting.respond_to?(:plugin_redmine_mail_handler) ? (Setting.plugin_redmine_mail_handler || {}) : {}
      return nil unless mh['dummy_mail_enabled'].to_s == '1'
      mh['dummy_mail_suffix'].to_s.strip.downcase.presence
    rescue
      nil
    end

    # Deliverable address of a mail sender (nil if only a dummy address exists).
    def sender_address(journal_user)
      suffix = dummy_mail_suffix
      user_addresses(journal_user).find { |a| a =~ EMAIL_RE && !(suffix && a.end_with?("@#{suffix}")) }
    end

    EMAIL_RE = /\A[^@\s]+@[^@\s]+\z/

    # Display name of a mail sender; drops the placeholder last name
    # redmine_mail_handler assigns to auto-created users ("Auto-generated").
    def sender_name(journal_user)
      return '' unless journal_user
      mh = Setting.respond_to?(:plugin_redmine_mail_handler) ? (Setting.plugin_redmine_mail_handler || {}) : {}
      placeholder = mh['user_lastname_custom'].to_s.strip
      if placeholder.present? && journal_user.lastname.to_s.strip.casecmp?(placeholder)
        journal_user.firstname.to_s.strip
      else
        journal_user.name.to_s
      end
    rescue
      journal_user.name.to_s
    end

    def contact_for_user(journal_user, project, user)
      return nil unless journal_user && !journal_user.anonymous? && defined?(Contact)
      addresses = user_addresses(journal_user)
      return nil if addresses.empty?
      scope = Contact.all
      scope = scope.by_project(project.id) if Contact.respond_to?(:by_project)
      scope = scope.visible(user)          if Contact.respond_to?(:visible)
      scope.where("#{Contact.table_name}.email IS NOT NULL AND #{Contact.table_name}.email <> ''").each do |c|
        mails = c.emails.map { |m| m.to_s.strip.downcase }
        return c if (mails & addresses).any?
      end
      nil
    rescue => e
      Rails.logger.warn("[redmine_sendmail] contact_for_user failed: #{e.class}: #{e.message}")
      nil
    end

    # ---- quoting ---------------------------------------------------------

    # Builds the "> " quoted block for the journal being replied to.
    def build_quote(journal, settings, lowercase: false)
      return '' unless journal && journal.notes.present?
      text = journal.notes.to_s.dup
      if email_origin?(journal)
        # Drop the subject line redmine_mail_handler prepends to the notes.
        lines = text.lines
        lines.shift
        lines.shift while lines.any? && lines.first.strip.empty?
        text = lines.join
      end
      text = Dispatcher.strip_inline_image_refs(text, journal_attachments(journal)).strip
      return '' if text.empty?

      author = journal.user ? journal.user.name.to_s : ''
      author = author.downcase if lowercase
      header_tpl = settings['quote_header_template'].presence || 'Am {quote_date} schrieb {quote_author}:'
      header = TemplateRenderer.render(header_tpl, {
        'quote_date'   => I18n.l(journal.created_on.to_date),
        'quote_time'   => I18n.l(journal.created_on, format: :time),
        'quote_author' => author
      }).strip
      quoted = text.gsub(/\r\n?/, "\n").split("\n", -1).map { |l| l.empty? ? '>' : "> #{l}" }.join("\n")
      header.present? ? "#{header}\n#{quoted}" : quoted
    end

    def journal_attachments(journal)
      ids = Dispatcher.journal_attachment_ids(journal)
      return [] if ids.empty? || !defined?(Attachment)
      Attachment.where(id: ids).to_a
    rescue
      []
    end

    # Places the quote in the rendered body. If the template contains a
    # `{quote}` placeholder it has already been substituted during rendering
    # (vars['quote']); otherwise the quote is appended at the very end, the
    # way mail clients put the quoted mail below the signature.
    def apply_quote(body, template, quote)
      return body.to_s if template.to_s.include?('{quote}')
      return body.to_s if quote.to_s.strip.empty?
      "#{body.to_s.rstrip}\n\n#{quote}"
    end
  end
end
