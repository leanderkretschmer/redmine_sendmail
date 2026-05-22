require_dependency File.expand_path('template_renderer', __dir__)
require_dependency File.expand_path('smtp_resolver', __dir__)
require_dependency File.expand_path('alias_resolver', __dir__)

module RedmineSendmail
  module Dispatcher
    module_function

    def dispatch_for_journal(journal:, params:, attachment_params: nil)
      return [] if params.blank?
      return [] unless journal && journal.notes.present?

      contact_ids = extract_contact_ids(params)
      if contact_ids.empty?
        Rails.logger.info("[redmine_sendmail] dispatcher: no contacts selected for journal ##{journal.id}")
        return []
      end

      custom_subject = params[:subject].to_s.strip
      issue          = journal.journalized
      project        = issue.project
      user           = journal.user || User.current

      settings    = Setting.plugin_redmine_sendmail || {}
      smtp_config = SmtpResolver.resolve(settings)
      attachments      = collect_attachments(journal: journal, issue: issue, attachment_params: attachment_params)
      attachments_data = build_attachments_data(attachments)
      cleaned_notes    = strip_inline_image_refs(journal.notes.to_s, attachments)
      Rails.logger.info("[redmine_sendmail] dispatcher: SMTP config = #{smtp_config ? smtp_config.except(:password).inspect : 'default ActionMailer'}; #{contact_ids.size} recipient(s); #{attachments_data.size} attachment(s) [#{attachments.map(&:filename).inspect}]")

      contact_ids.map do |cid|
        dispatch_one(
          issue:            issue,
          project:          project,
          journal:          journal,
          user:             user,
          contact_id:       cid,
          custom_subject:   custom_subject,
          settings:         settings,
          smtp_config:      smtp_config,
          attachments_data: attachments_data,
          comment_text:     cleaned_notes
        )
      end.compact
    end

    # Sends a freshly created issue as an e-mail: the issue subject becomes the
    # mail subject (via the configured subject template) and the issue
    # description — with inline image syntax stripped and the referenced files
    # attached — becomes the body.
    def dispatch_for_issue(issue:, params:, attachment_params: nil)
      return [] if params.blank?
      return [] unless issue

      contact_ids = extract_contact_ids(params)
      if contact_ids.empty?
        Rails.logger.info("[redmine_sendmail] dispatcher: no contacts selected for issue ##{issue.id}")
        return []
      end

      project = issue.project
      user    = issue.author || User.current

      settings    = Setting.plugin_redmine_sendmail || {}
      smtp_config = SmtpResolver.resolve(settings)
      attachments      = collect_issue_attachments(issue, attachment_params)
      attachments_data = build_attachments_data(attachments)
      cleaned_body     = strip_inline_image_refs(issue.description.to_s, attachments)
      Rails.logger.info("[redmine_sendmail] dispatcher: new issue ##{issue.id}; SMTP config = #{smtp_config ? smtp_config.except(:password).inspect : 'default ActionMailer'}; #{contact_ids.size} recipient(s); #{attachments_data.size} attachment(s) [#{attachments.map(&:filename).inspect}]")

      contact_ids.map do |cid|
        dispatch_one(
          issue:            issue,
          project:          project,
          journal:          nil,
          user:             user,
          contact_id:       cid,
          custom_subject:   issue.subject.to_s,
          settings:         settings,
          smtp_config:      smtp_config,
          attachments_data: attachments_data,
          comment_text:     cleaned_body
        )
      end.compact
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

    def dispatch_one(issue:, project:, journal:, user:, contact_id:, custom_subject:, settings:, smtp_config:, attachments_data: [], comment_text: nil)
      contact = lookup_contact(contact_id, project, user)
      unless contact
        Rails.logger.warn("[redmine_sendmail] contact ##{contact_id} not found / not visible — skipping")
        return nil
      end
      recipient_email = contact.primary_email.to_s.strip
      if recipient_email.blank?
        Rails.logger.warn("[redmine_sendmail] contact ##{contact_id} (#{contact.name}) has no e-mail — skipping")
        return nil
      end
      recipient_name = contact.name

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
        contact_id:      contact.id,
        recipient_email: recipient_email,
        recipient_name:  recipient_name,
        subject:         subject.first(998),
        body:            body,
        status:          'sent'
      )

      Rails.logger.info("[redmine_sendmail] dispatcher: sending to #{recipient_email} (issue ##{issue.id}, journal ##{journal&.id || '-'}, contact ##{contact.id}, from=#{from_email.inspect}, from_name=#{from_name.inspect}, reply_to=#{reply_to.inspect}, attachments=#{attachments_data.size})")
      begin
        delivered = RedmineSendmailMailer.dispatch(
          subject:          subject,
          body:             body,
          recipient_email:  recipient_email,
          recipient_name:   recipient_name,
          from_email:       from_email,
          from_name:        from_name,
          reply_to:         reply_to,
          extra_headers:    { 'X-Redmine-Issue' => issue.id.to_s, 'X-Redmine-Project' => project.identifier.to_s },
          smtp_config:      smtp_config,
          attachments_data: attachments_data
        ).deliver_now
        Rails.logger.info("[redmine_sendmail] dispatcher: deliver_now OK (message_id=#{delivered&.message_id.inspect}, body_size=#{body.to_s.bytesize})")
      rescue => e
        record.status = 'failed'
        record.error_message = "#{e.class}: #{e.message}"
        Rails.logger.error("[redmine_sendmail] delivery failed for #{recipient_email}: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}")
      end

      record.save if settings['log_dispatches'].to_s == '1' || record.status == 'failed'
      record
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
