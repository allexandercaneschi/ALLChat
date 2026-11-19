module ConversationAssignmentTargetsConcern
  private

  def validate_assignment_targets
    assignee_id = params[:assignee_id]
    return render_could_not_create_error('Invalid assignee_id') if assignee_id.present? && !Current.account.users.exists?(id: assignee_id)

    return render_assignment_forbidden unless assignee_allowed_on_create?(assignee_id)

    team_id = params[:team_id]
    return if team_id.blank? || Current.account.teams.exists?(id: team_id)

    render_could_not_create_error('Invalid team_id')
  end

  # ALLChat: a new conversation follows the same ownership rules as a later assignment, so the
  # create endpoint cannot be used to hand a conversation to someone else. API tokens keep direct control.
  def assignee_allowed_on_create?(assignee_id)
    return true if assignee_id.blank? || authenticate_by_access_token?

    new_conversation = Conversation.new(account: Current.account)
    Conversations::OwnershipRules.new(conversation: new_conversation, user: Current.user).assignment_decision(assignee_id) == :direct
  end

  def render_assignment_forbidden
    render json: { error: CustomExceptions::ConversationRequest::NotAllowed.new(reason: 'assignment').message }, status: :forbidden
  end
end
