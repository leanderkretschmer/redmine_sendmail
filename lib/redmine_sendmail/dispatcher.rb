require_dependency File.expand_path('template_renderer', __dir__)
require_dependency File.expand_path('smtp_resolver', __dir__)
require_dependency File.expand_path('alias_resolver', __dir__)
require_dependency File.expand_path('bounce_checker', __dir__)

module RedmineSendmail
  module Dispatcher
    module_function

    def dispatch_for_journal(journal:, params:, attachment_params: nil)
      return [] if params.blank?
      return [] unless journal && journal.notes.present?

      recipients = extract_recipients(params, journal.journalized&.project, journal.user || User.current)
      to_list  = recipients[:to]
      cc_list  = recipients[:cc]
      bcc_list = recipients[:bcc]
      Rails.logger.info("[redmine_sendmail] dispatcher: journal ##{journal.id} TO=#{to_list.size} CC=#{cc_list.size} BCC=#{bcc_list.size}")
      if to_list.empty? && cc_list.empty? && bcc_list.empty?
        Rails.logger.info("[redmine_sendmail] dispatcher: no recipients selected for journal ##{journal.id}")
        return []
      end

      custom_subject = params[:subject].to_s.strip
      issue          = journal.journalized
      project        = issue.project
      user           = journal.user || User.current

      global_settings = Setting.plugin_redmine_sendmail || {}
      project_setting = RedmineSendmailProjectSetting.for_project(project)
      settings        = RedmineSendmailProjectSetting.effective_settings(project, global_settings)
      smtp_config     = project_setting&.smtp_config_hash || SmtpResolver.resolve(global_settings)
      attachments      = collect_attachments(journal: journal, issue: issue, attachment_params: attachment_params)
      attachments_data = build_attachments_data(attachments)
      cleaned_notes    = strip_inline_image_refs(journal.notes.to_s, attachments)
      Rails.logger.info("[redmine_sendmail] dispatcher: SMTP config = #{smtp_config ? smtp_config.except(:password).inspect : 'default ActionMailer'}; #{to_list.size} TO recipient(s); #{attachments_data.size} attachment(s) [#{attachments.map(&:filename).inspect}]")

      dispatch_recipients(
        issue:            issue,
        project:          project,
        journal:          journal,
        user:             user,
        custom_subject:   custom_subject,
        comment_text:     cleaned_notes,
        settings:         settings,
        smtp_config:      smtp_config,
        attachments_data: attachments_data,
        to_list:          to_list,
        cc_list:          cc_list,
        bcc_list:         bcc_list
      )
    end

    # Sends a freshly created issue as an e-mail: the issue subject becomes the
    # mail subject (via the configured subject template) and the issue
    # description — with inline image syntax stripped and the referenced files
    # attached — becomes the body.
    def dispatch_for_issue(issue:, params:, attachment_params: nil)
      return [] if params.blank?
      return [] unless issue

      recipients = extract_recipients(params, issue.project, issue.author || User.current)
      to_list  = recipients[:to]
      cc_list  = recipients[:cc]
      bcc_list = recipients[:bcc]
      Rails.logger.info("[redmine_sendmail] dispatcher: new issue ##{issue.id} TO=#{to_list.size} CC=#{cc_list.size} BCC=#{bcc_list.size}")
      if to_list.empty? && cc_list.empty? && bcc_list.empty?
        Rails.logger.info("[redmine_sendmail] dispatcher: no recipients selected for issue ##{issue.id}")
        return []
      end

      project = issue.project
      user    = issue.author || User.current

      global_settings = Setting.plugin_redmine_sendmail || {}
      project_setting = RedmineSendmailProjectSetting.for_project(project)
      settings        = RedmineSendmailProjectSetting.effective_settings(project, global_settings)
      smtp_config     = project_setting&.smtp_config_hash || SmtpResolver.resolve(global_settings)
      attachments      = collect_issue_attachments(issue, attachment_params)
      attachments_data = build_attachments_data(attachments)
      cleaned_body     = strip_inline_image_refs(issue.description.to_s, attachments)
      custom_subject   = params[:subject].to_s.strip.presence || issue.subject.to_s
      Rails.logger.info("[redmine_sendmail] dispatcher: new issue ##{issue.id}; SMTP config = #{smtp_config ? smtp_config.except(:password).inspect : 'default ActionMailer'}; #{to_list.size} TO recipient(s); #{attachments_data.size} attachment(s) [#{attachments.map(&:filename).inspect}]")

      dispatch_recipients(
        issue:            issue,
        project:          project,
        journal:          nil,
        user:             user,
        custom_subject:   custom_subject,
        comment_text:     cleaned_body,
        settings:         settings,
        smtp_config:      smtp_config,
        attachments_data: attachments_data,
        to_list:          to_list,
        cc_list:          cc_list,
        bcc_list:         bcc_list
      )
    end

    # Iterates the TO list and sends one personalised mail per TO recipient;
    # each mail carries the configured CC/BCC list. If no TO recipient exists
    # (CC/BCC only), one mail is built from the first CC/BCC entry just so the
    # SMTP envelope has a `To:` header.
    def dispatch_recipients(issue:, project:, journal:, user:, custom_subject:, comment_text:, settings:, smtp_config:, attachments_data:, to_list:, cc_list:, bcc_list:)
      records = []
      effective_to = to_list.any? ? to_list : Array(cc_list.first || bcc_list.first)
      cc_for_send  = (to_list.any? ? cc_list  : cc_list.drop(to_list.empty? && cc_list.any?  ? 1 : 0))
      bcc_for_send = (to_list.any? ? bcc_list : (to_list.empty? && cc_list.empty? ? bcc_list.drop(1) : bcc_list))

      effective_to.each do |recipient|
        records << dispatch_one(
          issue:            issue,
          project:          project,
          journal:          journal,
          user:             user,
          recipient:        recipient,
          mode:             recipient[:mode] || 'to',
          custom_subject:   custom_subject,
          settings:         settings,
          smtp_config:      smtp_config,
          attachments_data: attachments_data,
          comment_text:     comment_text,
          cc_recipients:    cc_for_send,
          bcc_recipients:   bcc_for_send
        )
      end

      # Log CC/BCC recipients separately so the project log shows every recipient
      # individually with its mode — even though they share the same physical
      # mail with the TO recipient.
      cc_for_send.each do |r|
        records << log_recipient(issue: issue, project: project, journal: journal,
                                 user: user, recipient: r, mode: 'cc',
                                 subject: records.first&.subject || custom_subject,
                                 body: records.first&.body || comment_text,
                                 settings: settings)
      end
      bcc_for_send.each do |r|
        records << log_recipient(issue: issue, project: project, journal: journal,
                                 user: user, recipient: r, mode: 'bcc',
                                 subject: records.first&.subject || custom_subject,
                                 body: records.first&.body || comment_text,
                                 settings: settings)
      end

      records.compact
    end

    def build_attachments_data(attachments)
      Array(attachments).filter_map do |att|
        path = att.respond_to?(:diskfile) ? att.diskfile.to_s : nil
        if path.blank? || !File.exist?(path) || !File.readable?(path)
          Rails.logger.warn("[redmine_sendmail] attachment ##{att.id} (#{att.filename}) not readable on disk (#{path.inspect}) — skipping")
          next nil
        end
        {
          filename:     att.filename.to_s,
          content:      File.binread(path),
          content_type: att.respond_to?(:content_type) ? att.content_type.to_s : nil
        }
      rescue => e
        Rails.logger.warn("[redmine_sendmail] failed to read attachment ##{att.id}: #{e.class}: #{e.message}")
        nil
      end
    end

    def collect_attachments(journal:, issue:, attachment_params:)
      return [] unless defined?(Attachment)
      ids = []
      ids.concat(journal_attachment_ids(journal))
      ids.concat(token_attachment_ids(attachment_params))
      ids = ids.reject(&:zero?).uniq
      return [] if ids.empty?
      scope = Attachment.where(id: ids)
      if issue
        scope = scope.where(container_type: 'Issue', container_id: issue.id)
      end
      scope.to_a
    rescue => e
      Rails.logger.warn("[redmine_sendmail] failed to collect attachments: #{e.class}: #{e.message}")
      []
    end

    # For a freshly created issue all uploaded files are already attached to the
    # issue itself; we still merge any upload-token ids defensively.
    def collect_issue_attachments(issue, attachment_params)
      return [] unless issue
      list = Array(issue.attachments).dup
      token_ids = token_attachment_ids(attachment_params)
      if token_ids.any? && defined?(Attachment)
        existing = list.map(&:id)
        extra = Attachment.where(id: token_ids - existing,
                                 container_type: 'Issue', container_id: issue.id).to_a
        list.concat(extra)
      end
      list.uniq(&:id)
    rescue => e
      Rails.logger.warn("[redmine_sendmail] failed to collect issue attachments: #{e.class}: #{e.message}")
      Array(issue&.attachments)
    end

    def journal_attachment_ids(journal)
      return [] unless journal
      JournalDetail.where(journal_id: journal.id, property: 'attachment').pluck(:prop_key).map(&:to_i)
    rescue => e
      Rails.logger.warn("[redmine_sendmail] journal detail lookup failed: #{e.class}: #{e.message}")
      []
    end

    def token_attachment_ids(attachment_params)
      return [] unless attachment_params.is_a?(Hash)
      ids = []
      attachment_params.each_value do |attrs|
        next unless attrs.is_a?(Hash)
        token = attrs[:token] || attrs['token']
        next if token.to_s.empty?
        if token.to_s =~ /\A(\d+)\.[0-9a-f]+\z/
          ids << Regexp.last_match(1).to_i
        end
      end
      ids
    end

    # Redmine/Textile inline image syntax, e.g.
    #   !image.png!  /  !>image.png!  /  !{width:50%}image.png!  /  !image.png(alt)!:url
    # Pasted screenshots arrive URL-encoded in the comment
    # (!Bildschirmfoto%202026-05-22%20um%2013.23.43.png!) and therefore never
    # match an attachment filename literally — so we also strip by extension.
    INLINE_IMAGE_PATTERN = /
      !                                                  # opening marker
      (?:[<>=]|\{[^}]*\}|\([^)]*\)|\[[^\]]*\])*           # optional alignment \/ style \/ class
      [^\s!]+?                                            # image path \/ URL (no spaces)
      \.(?:png|jpe?g|gif|bmp|webp|svg|tiff?|heic|avif)    # image extension
      (?:\([^)]*\))?                                      # optional (alt text)
      !                                                  # closing marker
      (?::\S+)?                                           # optional :link suffix
    /xi

    def strip_inline_image_refs(text, attachments)
      result = text.to_s
      return result if result.empty?

      # 1) Remove references that match a real attachment filename — handles
      #    arbitrary extensions and the optional ":url" suffix.
      Array(attachments).each do |att|
        fn = att.filename.to_s
        next if fn.empty?
        escaped = Regexp.escape(fn)
        result = result.gsub(/![^!\n]*?#{escaped}[^!\n]*?!(?::\S+)?/, '')
      end

      # 2) Remove any remaining generic inline image syntax (URL-encoded names).
      result = result.gsub(INLINE_IMAGE_PATTERN, '')

      # Tidy up whitespace left behind by removed image lines.
      result = result.gsub(/[ \t]+$/, '')
      result.gsub(/\n{3,}/, "\n\n")
    end

    def extract_contact_ids(params)
      ids = params[:contact_ids]
      ids = ids.values if ids.is_a?(Hash)
      ids = Array(ids).flatten
      if ids.empty? && params[:contact_id].to_s.strip.present?
        ids = [params[:contact_id]]
      end
      ids.map { |v| v.to_s.strip }.reject(&:blank?).uniq
    end

    EMAIL_RE = /\A[^@\s]+@[^@\s]+\z/

    # Resolves the recipient list submitted from the form into structured
    # entries grouped by mode. Each entry is a hash:
    #   { contact_id: Integer|nil, name: String, email: String,
    #     mode: 'to'|'cc'|'bcc', adhoc: Boolean }
    #
    # `params` is the symbol-keyed Hash sent under `sendmail[...]`. It honours
    # the legacy `contact_ids` array (mode='to'), the per-contact mode map
    # under `contact_modes`, and the ad-hoc list under `adhoc`.
    def extract_recipients(params, project, user)
      contact_ids = extract_contact_ids(params)
      modes       = params[:contact_modes] || params['contact_modes'] || {}
      modes       = modes.to_unsafe_h if modes.respond_to?(:to_unsafe_h)
      modes       = modes.to_h        if modes.respond_to?(:to_h) && !modes.is_a?(Hash)

      to_list  = []
      cc_list  = []
      bcc_list = []

      contact_ids.each do |cid|
        contact = lookup_contact(cid, project, user)
        next unless contact
        email = contact.primary_email.to_s.strip
        next if email.blank?
        mode = normalize_mode(modes[cid] || modes[cid.to_s] || modes[cid.to_sym])
        entry = {
          contact_id: contact.id,
          name:       contact.name.to_s,
          email:      email,
          mode:       mode,
          adhoc:      false
        }
        case mode
        when 'cc'  then cc_list << entry
        when 'bcc' then bcc_list << entry
        else
          entry[:mode] = 'to'
          to_list << entry
        end
      end

      Array(params[:adhoc] || params['adhoc']).each_with_index do |row, _|
        row = row.last if row.is_a?(Array) # `adhoc[0][...]` form yields [key, value]
        next unless row.is_a?(Hash)
        email = (row[:email] || row['email']).to_s.strip
        next unless email =~ EMAIL_RE
        name  = (row[:name] || row['name']).to_s.strip
        mode  = normalize_mode(row[:mode] || row['mode'])
        entry = {
          contact_id: nil,
          name:       name,
          email:      email,
          mode:       mode,
          adhoc:      true
        }
        case mode
        when 'cc'  then cc_list << entry
        when 'bcc' then bcc_list << entry
        else
          entry[:mode] = 'to'
          to_list << entry
        end
      end

      { to: dedupe_by_email(to_list),
        cc: dedupe_by_email(cc_list),
        bcc: dedupe_by_email(bcc_list) }
    end

    def normalize_mode(value)
      v = value.to_s.downcase.strip
      return v if %w[to cc bcc].include?(v)
      'to'
    end

    def dedupe_by_email(list)
      seen = {}
      list.each do |entry|
        key = entry[:email].downcase
        seen[key] ||= entry
      end
      seen.values
    end

    def dispatch_one(issue:, project:, journal:, user:, recipient:, mode: 'to', custom_subject:, settings:, smtp_config:, attachments_data: [], comment_text: nil, cc_recipients: [], bcc_recipients: [])
      recipient_email = recipient[:email].to_s.strip
      if recipient_email.blank?
        Rails.logger.warn("[redmine_sendmail] dispatch_one: blank recipient email — skipping")
        return nil
      end
      recipient_name = recipient[:name].to_s
      contact = recipient[:contact_id] ? lookup_contact(recipient[:contact_id], project, user) : nil

      vars = TemplateRenderer.build_vars(
        user:            user,
        issue:           issue,
        contact:         contact,
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        custom_subject:  custom_subject,
        comment:         comment_text.presence || journal&.notes,
        settings:        settings
      )
      kennung = contact ? RedmineSendmailContactProjectKennung.value_for(contact, project) : ''
      vars['kunden-projekt-kennung'] = kennung
      vars['kunden_projekt_kennung'] = kennung

      subject_template = settings['subject_template'].presence || '[#{ticket_id}] {custom_subject}'
      body_template    = settings['body_template'].to_s
      subject = TemplateRenderer.render(subject_template, vars).strip
      subject = "[##{issue.id}]" if subject.blank?
      body    = TemplateRenderer.render(body_template, vars)

      project_alias = resolve_project_alias(settings, project)
      from_email    = project_alias || resolve_from(settings, vars)
      reply_to      = project_alias || resolve_reply_to(settings, vars)
      from_name     = TemplateRenderer.render(settings['from_name'].to_s, vars).strip.presence

      record = RedmineSendmailDispatch.new(
        issue_id:        issue.id,
        journal_id:      journal&.id,
        project_id:      project.id,
        user_id:         user.id,
        contact_id:      recipient[:contact_id],
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        subject:         subject.first(998),
        body:            body,
        status:          'sent',
        mode:            mode,
        is_adhoc:        recipient[:adhoc] ? true : false
      )

      Rails.logger.info("[redmine_sendmail] dispatcher: sending to #{recipient_email} mode=#{mode} (issue ##{issue.id}, journal ##{journal&.id || '-'}, contact ##{recipient[:contact_id] || '-'}, from=#{from_email.inspect}, from_name=#{from_name.inspect}, reply_to=#{reply_to.inspect}, cc=#{cc_recipients.size}, bcc=#{bcc_recipients.size}, attachments=#{attachments_data.size})")
      begin
        delivered = RedmineSendmailMailer.dispatch(
          subject:          subject,
          body:             body,
          recipient_email:  recipient_email,
          recipient_name:   recipient_name,
          from_email:       from_email,
          from_name:        from_name,
          reply_to:         reply_to,
          cc:               cc_recipients,
          bcc:              bcc_recipients,
          extra_headers:    { 'X-Redmine-Issue' => issue.id.to_s, 'X-Redmine-Project' => project.identifier.to_s },
          smtp_config:      smtp_config,
          attachments_data: attachments_data
        ).deliver_now
        Rails.logger.info("[redmine_sendmail] dispatcher: deliver_now OK (message_id=#{delivered&.message_id.inspect}, body_size=#{body.to_s.bytesize})")
      rescue => e
        record.status = 'failed'
        record.error_message = "#{e.class}: #{e.message}"
        record.failure_reason_detail = BounceChecker.analyze(recipient_email, record.error_message)
        Rails.logger.error("[redmine_sendmail] delivery failed for #{recipient_email}: #{e.class}: #{e.message} (diagnosis=#{record.failure_reason_detail.inspect})\n#{Array(e.backtrace).first(5).join("\n")}")
      end

      record.save if settings['log_dispatches'].to_s == '1' || record.status == 'failed'
      record
    end

    # Persists a log row for a recipient that shares an already-sent mail
    # (i.e. CC or BCC of the TO mail). The mail is NOT re-delivered — this
    # only records the recipient in the dispatch log so the per-project
    # overview shows every addressee individually.
    def log_recipient(issue:, project:, journal:, user:, recipient:, mode:, subject:, body:, settings:)
      return nil unless settings['log_dispatches'].to_s == '1'
      record = RedmineSendmailDispatch.new(
        issue_id:        issue.id,
        journal_id:      journal&.id,
        project_id:      project.id,
        user_id:         user.id,
        contact_id:      recipient[:contact_id],
        recipient_email: recipient[:email].to_s,
        recipient_name:  recipient[:name].to_s,
        subject:         subject.to_s.first(998),
        body:            body.to_s,
        status:          'sent',
        mode:            mode,
        is_adhoc:        recipient[:adhoc] ? true : false
      )
      record.save
      record
    end

    # Re-sends a previously logged dispatch using the saved subject/body
    # and the *current* sender / SMTP configuration. Inline attachments are
    # not re-attached (the user can re-send from the original comment for
    # that). A new RedmineSendmailDispatch row is always created so the
    # original failed entry remains in the log for traceability.
    def resend(dispatch)
      return nil unless dispatch
      project = Project.find_by(id: dispatch.project_id)
      unless project
        Rails.logger.warn("[redmine_sendmail] resend ##{dispatch.id}: project ##{dispatch.project_id} not found")
        return nil
      end

      global_settings = Setting.plugin_redmine_sendmail || {}
      project_setting = RedmineSendmailProjectSetting.for_project(project)
      settings        = RedmineSendmailProjectSetting.effective_settings(project, global_settings)
      smtp_config     = project_setting&.smtp_config_hash || SmtpResolver.resolve(global_settings)

      info_1, info_2 = RedmineSendmailProjectSetting.values_for(project)
      identifier     = project.identifier.to_s
      projekt_kennung = TemplateRenderer.slice_identifier(identifier, settings['project_identifier_slice'])
      kunden_kennung  = RedmineSendmailContactProjectKennung.value_for(dispatch.contact_id, project)
      vars = {
        'recipient_email'     => dispatch.recipient_email.to_s,
        'recipient_name'      => dispatch.recipient_name.to_s,
        'project_name'        => project.name.to_s,
        'project_identifier'  => identifier,
        'projekt-kennung'     => projekt_kennung,
        'projekt_kennung'     => projekt_kennung,
        'project_info_1'      => info_1,
        'project_info_2'      => info_2,
        'project-info-1'      => info_1,
        'project-info-2'      => info_2,
        'kunden-projekt-kennung' => kunden_kennung,
        'kunden_projekt_kennung' => kunden_kennung
      }

      project_alias = resolve_project_alias(settings, project)
      from_email    = project_alias || resolve_from(settings, vars)
      reply_to      = project_alias || resolve_reply_to(settings, vars)
      from_name     = TemplateRenderer.render(settings['from_name'].to_s, vars).strip.presence

      new_record = RedmineSendmailDispatch.new(
        issue_id:        dispatch.issue_id,
        journal_id:      dispatch.journal_id,
        project_id:      dispatch.project_id,
        user_id:         User.current.id || dispatch.user_id,
        contact_id:      dispatch.contact_id,
        recipient_email: dispatch.recipient_email,
        recipient_name:  dispatch.recipient_name,
        subject:         dispatch.subject,
        body:            dispatch.body,
        status:          'sent'
      )

      Rails.logger.info("[redmine_sendmail] resend ##{dispatch.id} → #{dispatch.recipient_email} (from=#{from_email.inspect})")
      begin
        RedmineSendmailMailer.dispatch(
          subject:         dispatch.subject,
          body:            dispatch.body,
          recipient_email: dispatch.recipient_email,
          recipient_name:  dispatch.recipient_name,
          from_email:      from_email,
          from_name:       from_name,
          reply_to:        reply_to,
          extra_headers:   {
            'X-Redmine-Issue'           => dispatch.issue_id.to_s,
            'X-Redmine-Project'         => project.identifier.to_s,
            'X-Redmine-Sendmail-Resend' => dispatch.id.to_s
          },
          smtp_config:     smtp_config,
          attachments_data: []
        ).deliver_now
      rescue => e
        new_record.status = 'failed'
        new_record.error_message = "#{e.class}: #{e.message}"
        new_record.failure_reason_detail = BounceChecker.analyze(dispatch.recipient_email, new_record.error_message)
        Rails.logger.error("[redmine_sendmail] resend ##{dispatch.id} failed: #{e.class}: #{e.message} (diagnosis=#{new_record.failure_reason_detail.inspect})")
      end

      new_record.save
      new_record
    end

    def resolve_project_alias(settings, project)
      return nil unless settings['use_project_alias'].to_s == '1'
      email = AliasResolver.alias_for_project(project)
      Rails.logger.info("[redmine_sendmail] dispatcher: project alias for ##{project.id} -> #{email.inspect}")
      email
    end

    def resolve_from(settings, vars = {})
      explicit = TemplateRenderer.render(settings['from_email'].to_s, vars).strip
      return explicit if explicit.present?
      mh = SmtpResolver.mail_handler_account_email
      return mh if mh
      fallback = (Setting.mail_from rescue nil).to_s.strip
      fallback.presence
    end

    def resolve_reply_to(settings, vars = {})
      explicit = TemplateRenderer.render(settings['reply_to_email'].to_s, vars).strip
      return explicit if explicit.present?
      SmtpResolver.mail_handler_account_email
    end

    def lookup_contact(contact_id, project, user)
      return nil if contact_id.blank?
      return nil unless defined?(Contact)
      scope = Contact.where(id: contact_id)
      scope = scope.by_project(project.id) if Contact.respond_to?(:by_project)
      scope = scope.visible(user)          if Contact.respond_to?(:visible)
      scope.first
    end
  end
end
