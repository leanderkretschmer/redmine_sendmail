class RedmineSendmailDispatchesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  helper :sort
  include SortHelper

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
    params.require(:redmine_sendmail_project_setting).permit(:info_1, :info_2)
  rescue ActionController::ParameterMissing
    {}
  end
end
