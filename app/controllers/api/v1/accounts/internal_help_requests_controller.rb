# ALLChat: "ask for help". The request is addressed to ONE person chosen by the sender (a colleague or a
# superior) and lives in the direct channel between them. There is no way to address a team or everyone.
class Api::V1::Accounts::InternalHelpRequestsController < Api::V1::Accounts::BaseController
  def create
    recipient = Current.account.users.find(single_recipient_id)
    raise ActionController::ParameterMissing, 'recipient_id must be another agent' if recipient.id == Current.user.id

    channel = InternalChat::Channel.find_or_create_direct!(Current.account, Current.user, recipient)
    authorize InternalChat::Message.new(channel: channel), :create?
    message = InternalChat::Messages::CreateService.new(
      channel: channel, sender: Current.user, content: params.require(:content), kind: :help_request,
      recipient: recipient, conversation: help_request_conversation
    ).perform
    render json: message.push_event_data
  end

  private

  def single_recipient_id
    recipient_id = params.require(:recipient_id)
    raise ActionController::ParameterMissing, 'recipient_id must be a single user' unless recipient_id.to_s.match?(/\A\d+\z/)

    recipient_id
  end

  def help_request_conversation
    return if params[:conversation_id].blank?

    Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end
end
