class RedmineSendmailContactKennungenController < ApplicationController
  before_action :find_project_by_project_id
  before_action :require_admin

  def update
    contact_id = params[:contact_id].to_i
    if contact_id <= 0
      flash[:error] = 'Missing contact_id'
      redirect_back(fallback_location: home_path) and return
    end

    value = params[:value].to_s.strip
    RedmineSendmailContactProjectKennung.upsert_value(
      contact_id: contact_id,
      project_id: @project.id,
      value:      value
    )
    flash[:notice] = l(:notice_successful_update)
    redirect_back(fallback_location: project_path(@project))
  end
end
