class RedmineSendmailDispatchesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :require_admin, only: [:update_project_settings, :resend]
  before_action :authorize,     except: [:update_project_settings, :resend]

  accept_api_auth :index, :show

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
      error_message:         d.error_message,
      failure_reason_detail: d.failure_reason_detail
    }
  end
end
