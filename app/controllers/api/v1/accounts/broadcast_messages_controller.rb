# ALLChat: scheduled broadcasts (agenda). Only administrators manage them.
class Api::V1::Accounts::BroadcastMessagesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_broadcast, only: [:update, :destroy]

  def index
    broadcasts = Current.account.broadcast_messages.includes(:broadcast_list).order(:name)
    render json: { payload: broadcasts.map(&:as_json_for_dashboard) }
  end

  def create
    broadcast = Current.account.broadcast_messages.create!(broadcast_params.merge(created_by_id: Current.user.id))
    render json: broadcast.as_json_for_dashboard
  end

  def update
    @broadcast.update!(broadcast_params)
    render json: @broadcast.as_json_for_dashboard
  end

  def destroy
    @broadcast.destroy!
    head :ok
  end

  private

  def fetch_broadcast
    @broadcast = Current.account.broadcast_messages.find(params[:id])
  end

  def broadcast_params
    attributes = params.require(:broadcast_message).permit(
      :broadcast_list_id, :inbox_id, :team_id, :name, :content, :schedule_kind, :run_at, :month, :day, :weekday, :week_of_month,
      :send_time, :send_email, :name_fallback, :resolve_after_hours, :active
    )
    Current.account.broadcast_lists.find(attributes[:broadcast_list_id]) if attributes.key?(:broadcast_list_id)
    Current.account.inboxes.find(attributes[:inbox_id]) if attributes.key?(:inbox_id)
    Current.account.teams.find(attributes[:team_id]) if attributes[:team_id].present?
    attributes
  end
end
