# ALLChat: "ask for help". The request goes to ONE person chosen by the sender (a colleague or a superior)
# or to the whole team the sender belongs to. Whoever knows how to help takes it. There is no way to
# address the whole account.
class Api::V1::Accounts::InternalHelpRequestsController < Api::V1::Accounts::BaseController
  def create
    channel = recipient ? direct_channel : team_channel
    authorize InternalChat::Message.new(channel: channel), :create?
    message = InternalChat::Messages::CreateService.new(
      channel: channel, sender: Current.user, content: params.require(:content), kind: :help_request,
      recipient: recipient, conversation: help_request_conversation
    ).perform
    render json: message.push_event_data
  end

  private

  # Exactly one audience: recipient_id (one person) or team_id (a team).
  def recipient
    return @recipient if defined?(@recipient)

    raise ActionController::ParameterMissing, 'send either recipient_id or team_id' if params[:recipient_id].present? == params[:team_id].present?

    @recipient = params[:recipient_id].present? ? find_recipient : nil
  end

  def find_recipient
    recipient_id = params[:recipient_id]
    raise ActionController::ParameterMissing, 'recipient_id must be a single user' unless recipient_id.to_s.match?(/\A\d+\z/)

    user = Current.account.users.find(recipient_id)
    raise ActionController::ParameterMissing, 'recipient_id must be another agent' if user.id == Current.user.id

    user
  end

  def direct_channel
    InternalChat::Channel.find_or_create_direct!(Current.account, Current.user, recipient)
  end

  def team_channel
    team = Current.account.teams.find(params[:team_id])
    room = InternalChat::Channel.new(account: Current.account, kind: :team_room, team: team)
    authorize room, :create?
    InternalChat::Channel.find_or_create_for_team!(Current.account, team)
  end

  def help_request_conversation
    return if params[:conversation_id].blank?

    Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end
end
