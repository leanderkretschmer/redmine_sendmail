module RedmineSendmail
  module AliasResolver
    module_function

    # Returns the first alias e-mail mapped to the given project by the
    # redmine_mail_handler address matrix, or nil if none matches / the
    # mail_handler plugin is unavailable.
    def alias_for_project(project)
      return nil unless project
      mapping = fetch_mapping
      return nil if mapping.blank?
      project_id = project.respond_to?(:id) ? project.id : project.to_i
      mapping.each do |email, prj|
        next if prj.nil?
        prj_id = prj.respond_to?(:id) ? prj.id : prj.to_i
        next unless prj_id == project_id
        candidate = email.to_s.strip
        return candidate if candidate.match?(/\A[^@\s]+@[^@\s]+\z/)
      end
      nil
    end

    def fetch_mapping
      return nil unless defined?(MailHandlerService)
      return nil unless MailHandlerService.respond_to?(:alias_project_mapping)
      MailHandlerService.alias_project_mapping
    rescue => e
      Rails.logger.warn("[redmine_sendmail] MailHandlerService.alias_project_mapping failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
