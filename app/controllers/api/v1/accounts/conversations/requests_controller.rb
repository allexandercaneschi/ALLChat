# ALLChat: transfer and participation requests of one conversation.
class Api::V1::Accounts::Conversations::RequestsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from CustomExceptions::ConversationRequest::Error, with: :render_error_response

  def index
    requests = ConversationRequest.where(conversation: @conversation).involving(Current.user)
    requests = requests.open_requests.or(requests.participation.accepted.where(target_id: @conversation.assignee_id))
    render json: { payload: requests.includes(:requester, :target).order(:created_at).map(&:push_event_data) }
  end

  # Asks the current assignee to let the agent reply in the conversation.
  def create
    raise CustomExceptions::ConversationRequest::NotAllowed.new(reason: 'participation') unless participation_allowed?

    request = ConversationRequest.create!(
      conversation: @conversation,
      requester: Current.user,
      target: @conversation.assignee,
      request_type: :participation
    )
    render json: request.push_event_data, status: :created
  end

  private

  def participation_allowed?
    return false unless Current.user.is_a?(User)

    rules = Conversations::OwnershipRules.new(conversation: @conversation, user: Current.user)
    @conversation.assignee_id.present? && !rules.can_reply?
  end
end
