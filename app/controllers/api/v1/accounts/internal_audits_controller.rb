# ALLChat: audit of internal conversations. Administrators read every conversation of the account and
# each supervisor reads the ones of their teams. Every read is written to InternalChat::AuditLog.
class Api::V1::Accounts::InternalAuditsController < Api::V1::Accounts::BaseController
  PAGE_SIZE = 50

  def index
    authorize InternalChat::Channel, policy_class: InternalChat::AuditPolicy
    channels = auditable_channels.includes(:team).order(updated_at: :desc).limit(PAGE_SIZE).to_a
    render json: { payload: channels.map { |channel| channel_json(channel) } }
  end

  def show
    channel = auditable_channels.find(params[:id])
    authorize channel, :show?, policy_class: InternalChat::AuditPolicy
    InternalChat::AuditLog.create!(account: Current.account, auditor: Current.user, channel: channel, action: 'read_messages')
    render json: { channel: channel_json(channel) }.merge(messages_page(channel))
  end

  private

  def messages_page(channel)
    messages = channel.messages.includes(:sender, :claimed_by).order(id: :desc).limit(PAGE_SIZE + 1)
    messages = messages.where(id: ...params[:before_id].to_i) if params[:before_id].present?
    page = messages.to_a
    { payload: page.first(PAGE_SIZE).reverse.map(&:push_event_data), meta: { has_more: page.size > PAGE_SIZE } }
  end

  def auditable_channels
    InternalChat::Channel.auditable_by(Current.user, Current.account_user, Current.account)
  end

  def channel_json(channel)
    {
      id: channel.id,
      kind: channel.kind,
      team: channel.team_room? ? { id: channel.team&.id, name: channel.team&.name } : nil,
      name: channel.company_room? ? Current.account.name : nil,
      participants: channel.direct? ? channel.members.map(&:push_event_data) : []
    }
  end
end
