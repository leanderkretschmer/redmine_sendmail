class RedmineSendmailDispatchesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :require_admin, only: [:update_project_settings]
  before_action :authorize,     except: [:update_project_settings]

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

    @limit = per_page_option
    scope = RedmineSendmailDispatch.for_project(@project).order(sort_clause)
    @dispatch_count = scope.count
    @dispatch_pages = Redmine::Pagination::Paginator.new(@dispatch_count, @limit, params['page'])
    @dispatches = scope.limit(@limit).offset(@dispatch_pages.offset).to_a
  end

  def show
    @dispatch = RedmineSendmailDispatch.where(project_id: @project.id).find(params[:id])
  end

  def update_project_settings
    setting = RedmineSendmailProjectSetting.find_or_initialize_by(project_id: @project.id)
    setting.attributes = project_settings_params
    if setting.save
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = setting.errors.full_messages.join(', ')
    end
    redirect_to settings_project_path(@project, tab: 'redmine_sendmail')
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
end
