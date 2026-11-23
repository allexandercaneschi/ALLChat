# Someone takes a help request. The first one wins. From then on the requester and who took it talk in
# their direct conversation, and the new person joins the customer conversation (if the request points to
# one) as a participant, so the information is not passed along second hand. Changing who is responsible
# for the customer conversation stays a decision of the two, through the usual transfer request.
class InternalChat::HelpRequests::ClaimService
  pattr_initialize [:message!, :user!]

  def perform
    message.claim!(user)
    InternalChat::Messages::CreateService.broadcast(message, InternalChat::Messages::CreateService::MESSAGE_UPDATED_EVENT)
    direct_channel = InternalChat::Channel.find_or_create_direct!(message.account, user, message.sender)
    InternalChat::Messages::CreateService.new(
      channel: direct_channel, sender: user, content: I18n.t('internal_chat.claimed_message', content: message.content.truncate(80))
    ).perform
    { message: message, channel: direct_channel, joined_conversation: join_conversation }
  end

  private

  def join_conversation
    return false if message.conversation.blank?

    participant = message.conversation.conversation_participants.find_or_initialize_by(user: user)
    participant.persisted? || participant.save
  end
end
