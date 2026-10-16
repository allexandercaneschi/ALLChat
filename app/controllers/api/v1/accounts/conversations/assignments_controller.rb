class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from CustomExceptions::ConversationRequest::Error, with: :render_error_response

  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  def set_agent
    case assignment_decision
    when :forbidden
      raise CustomExceptions::ConversationRequest::NotAllowed.new(reason: 'assignment')
    when :transfer_request
      return create_transfer_request
    end

    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    team_id = params[:team_id].to_i
    @team = team_id.positive? ? Current.account.teams.find(team_id) : nil
    @conversation.with_lock do
      @conversation.update!(team: @team)
    end
    render json: @team
  end

  # ALLChat: dashboard assignments follow Conversations::OwnershipRules; API tokens assign directly.
  def assignment_decision
    return :direct if authenticate_by_access_token?

    rules = Conversations::OwnershipRules.new(conversation: @conversation, user: Current.user)
    return rules.assignment_decision(params[:assignee_id]) unless agent_bot_assignment?

    # Handing over to a bot follows the same rule as releasing the conversation.
    rules.assignment_decision(nil) == :direct || @conversation.assignee_id.nil? ? :direct : :forbidden
  end

  def create_transfer_request
    request = ConversationRequest.create!(
      conversation: @conversation,
      requester: Current.user,
      target: Current.account.users.find(params[:assignee_id]),
      request_type: :transfer
    )
    render json: { conversation_request: request.push_event_data }, status: :accepted
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end
end

Api::V1::Accounts::Conversations::AssignmentsController.prepend_mod_with(
  'Api::V1::Accounts::Conversations::AssignmentsController'
)
