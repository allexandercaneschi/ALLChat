# ALLChat: the current agent's open transfer and participation requests.
class Api::V1::Accounts::ConversationRequestsController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::ConversationRequest::Error, with: :render_error_response
  before_action :fetch_request, except: :index

  def index
    requests = ConversationRequest.where(account: Current.account).involving(Current.user).open_requests
    render json: { payload: requests.includes(:requester, :target, conversation: :contact).order(:created_at).map(&:push_event_data) }
  end

  def accept
    ensure_participant!(@request.target_id)
    @request.accept!
    render json: @request.push_event_data
  end

  def decline
    ensure_participant!(@request.target_id)
    @request.decline!
    render json: @request.push_event_data
  end

  def cancel
    ensure_participant!(@request.requester_id)
    @request.cancel!
    render json: @request.push_event_data
  end

  private

  def fetch_request
    @request = ConversationRequest.where(account: Current.account).find(params[:id])
  end

  def ensure_participant!(user_id)
    raise CustomExceptions::ConversationRequest::NotAllowed.new(reason: 'respond') unless Current.user.is_a?(User) && user_id == Current.user.id
  end
end
