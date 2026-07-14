class RedmineSendmailDispatchesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :require_admin, only: [:update_project_settings, :resend]
  before_action :authorize,     except: [:update_project_settings, :resend]

  accept_api_auth :index, :show, :preview

  helper :sort
  include SortHelper

  PERMITTED_PROJECT_SETTINGS = %i[
    info_1 info_2
    body_template subject_template
    from_email from_name reply_to_email
    use_custom_smtp smtp_use_mail_handler
    smtp_host smtp_port smtp_ssl smtp_starttls
    smtp_authentication smtp_username smtp_password smtp_domain
  ].freeze

  def index
    sort_init 'created_at', 'desc'
    sort_update %w[created_at recipient_email subject status]

    scope = RedmineSendmailDispatch.for_project(@project)
    scope = scope.where(journal_id: params[:journal_id]) if params[:journal_id].present?
    scope = scope.where(issue_id:   params[:issue_id])   if params[:issue_id].present?
    scope = scope.order(sort_clause)

    respond_to do |format|
      format.html do
        @limit = per_page_option
        @dispatch_count = scope.count
        @dispatch_pages = Redmine::Pagination::Paginator.new(@dispatch_count, @limit, params['page'])
        @dispatches = scope.limit(@limit).offset(@dispatch_pages.offset).to_a
      end
      format.api do
        @dispatches = scope.to_a
        render json: { dispatches: @dispatches.map { |d| dispatch_as_json(d) }, total_count: @dispatches.size }
      end
      format.json do
        @dispatches = scope.to_a
        render json: { dispatches: @dispatches.map { |d| dispatch_as_json(d) }, total_count: @dispatches.size }
      end
    end
  end

  def show
    @dispatch = RedmineSendmailDispatch.where(project_id: @project.id).find(params[:id])
    respond_to do |format|
      format.html
      format.api  { render json: { dispatch: dispatch_as_json(@dispatch) } }
      format.json { render json: { dispatch: dispatch_as_json(@dispatch) } }
    end
  end

  def resend
    dispatch = RedmineSendmailDispatch.where(project_id: @project.id).find(params[:id])
    new_record = RedmineSendmail::Dispatcher.resend(dispatch)
    if new_record.nil?
      flash[:error] = l(:notice_sendmail_resend_failed)
    elsif new_record.sent?
      flash[:notice] = l(:notice_sendmail_resend_queued)
    else
      flash[:error] = new_record.error_message.presence || l(:notice_sendmail_resend_failed)
    end
    redirect_to project_sendmail_dispatch_path(@project, dispatch)
  end

  def preview
    sm = params[:sendmail].respond_to?(:to_unsafe_h) ? params[:sendmail].to_unsafe_h : (params[:sendmail] || {}).to_h
    sm = sm.deep_symbolize_keys
    user = User.current

    recipients = RedmineSendmail::Dispatcher.extract_recipients(sm, @project, user)
    to_list  = recipients[:to]
    cc_list  = recipients[:cc]
    bcc_list = recipients[:bcc]
    if to_list.empty? && cc_list.empty? && bcc_list.empty?
      render json: { error: 'no_recipients' }, status: 422
      return
    end

    issue = if params[:issue_id].to_s.present?
              Issue.find_by(id: params[:issue_id])
            else
              nil
            end
    issue ||= Issue.new(project: @project, subject: params[:ticket_subject].to_s, description: params[:body].to_s)

    first_recipient = to_list.first || cc_list.first || bcc_list.first
    contact_for_vars = first_recipient[:contact_id] ?
                       RedmineSendmail::Dispatcher.lookup_contact(first_recipient[:contact_id], @project, user) :
                       nil

    global_settings = Setting.plugin_redmine_sendmail || {}
    settings        = RedmineSendmailProjectSetting.effective_settings(@project, global_settings)

    custom_subject = params[:subject].to_s
    body_input     = params[:body].to_s

    vars = RedmineSendmail::TemplateRenderer.build_vars(
      user:            user,
      issue:           issue,
      contact:         contact_for_vars,
      recipient_email: first_recipient[:email],
      recipient_name:  first_recipient[:name],
      custom_subject:  custom_subject,
      comment:         body_input,
      settings:        settings
    )
    kennung = contact_for_vars ? RedmineSendmailContactProjectKennung.value_for(contact_for_vars, @project) : ''
    vars['kunden-projekt-kennung'] = kennung
    vars['kunden_projekt_kennung'] = kennung

    subject_template = settings['subject_template'].presence || '[#{ticket_id}] {custom_subject}'
    body_template    = settings['body_template'].to_s
    rendered_subject = RedmineSendmail::TemplateRenderer.render(subject_template, vars).strip
    rendered_subject = "[##{issue.id}]" if rendered_subject.blank?
    rendered_body    = RedmineSendmail::TemplateRenderer.render(body_template, vars)

    from_email = RedmineSendmail::Dispatcher.resolve_project_alias(settings, @project) ||
                 RedmineSendmail::Dispatcher.resolve_from(settings, vars)
    reply_to   = RedmineSendmail::Dispatcher.resolve_project_alias(settings, @project) ||
                 RedmineSendmail::Dispatcher.resolve_reply_to(settings, vars)
    from_name  = RedmineSendmail::TemplateRenderer.render(settings['from_name'].to_s, vars).strip.presence

    attachments = Array(params[:attachments])
                    .map { |n| n.to_s.strip }
                    .reject(&:blank?)
                    .uniq

    render json: {
      subject:         rendered_subject,
      body:            rendered_body,
      from:            from_email,
      from_name:       from_name,
      reply_to:        reply_to,
      attachments:     attachments,
      to_recipients:   to_list.map  { |r| public_recipient(r) },
      cc_recipients:   cc_list.map  { |r| public_recipient(r) },
      bcc_recipients:  bcc_list.map { |r| public_recipient(r) },
      recipient_count: to_list.size + cc_list.size + bcc_list.size,
      first_recipient: public_recipient(first_recipient)
    }
  rescue => e
    Rails.logger.error("[redmine_sendmail] preview failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: 'render_failed', message: e.message }, status: 500
  end

  def update_project_settings
    setting = RedmineSendmailProjectSetting.find_or_initialize_by(project_id: @project.id)
    setting.attributes = project_settings_params
    if setting.save
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = setting.errors.full_messages.join(', ')
    end
    redirect_to settings_project_path(@project, tab: 'sendmail')
  end

  private

  def project_settings_params
    permitted = params.require(:redmine_sendmail_project_setting).permit(*PERMITTED_PROJECT_SETTINGS)
    # Empty password field on edit must not clobber the stored credential.
    permitted.delete(:smtp_password) if permitted[:smtp_password].to_s.empty?
    permitted
  rescue ActionController::ParameterMissing
    {}
  end

  def dispatch_as_json(d)
    {
      id:                    d.id,
      created_at:            d.created_at,
      project_id:            d.project_id,
      issue_id:              d.issue_id,
      journal_id:            d.journal_id,
      user_id:               d.user_id,
      contact_id:            d.contact_id,
      recipient_name:        d.recipient_name,
      recipient_email:       d.recipient_email,
      subject:               d.subject,
      status:                d.status,
      mode:                  d.mode,
      is_adhoc:              d.is_adhoc,
      error_message:         d.error_message,
      failure_reason_detail: d.failure_reason_detail
    }
  end

  def public_recipient(r)
    return nil if r.blank?
    {
      name:       r[:name].to_s,
      email:      r[:email].to_s,
      mode:       r[:mode].to_s,
      contact_id: r[:contact_id],
      adhoc:      r[:adhoc] ? true : false
    }
  end
end
