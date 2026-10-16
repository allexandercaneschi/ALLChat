# ALLChat: who may reply to or reassign a conversation from the dashboard.
#
# - Nobody replies publicly to an unassigned conversation.
# - The assignee replies; administrators, supervisors and agents whose
#   participation request was accepted by the current assignee also reply.
# - Administrators and supervisors assign directly.
# - Agents take unassigned conversations, release their own, and hand their
#   own conversations to someone else through a transfer request.
class Conversations::OwnershipRules
  pattr_initialize [:conversation!, :user!]

  def can_reply?
    return false if conversation.assignee_id.blank?

    owner? || manager? || authorized_participant?
  end

  # Returns :direct, :transfer_request or :forbidden for assigning the conversation to assignee_id.
  def assignment_decision(assignee_id)
    return :direct if manager?

    target_id = assignee_id.presence&.to_i
    return assign_to_self_decision if target_id == user.id
    return :forbidden unless owner?

    target_id.nil? ? :direct : :transfer_request
  end

  def manager?
    account_user&.administrator_or_supervisor?
  end

  def owner?
    conversation.assignee_id == user.id
  end

  private

  def assign_to_self_decision
    conversation.assignee_id.nil? || owner? ? :direct : :forbidden
  end

  def authorized_participant?
    ConversationRequest.participation.accepted.exists?(
      conversation_id: conversation.id, requester_id: user.id, target_id: conversation.assignee_id
    )
  end

  def account_user
    @account_user ||= conversation.account.account_users.find_by(user_id: user.id)
  end
end
