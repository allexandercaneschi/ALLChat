# ALLChat: internal chat channels of the current agent (direct conversations and team rooms).
class Api::V1::Accounts::InternalChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: :read

  def index
    authorize InternalChat::Channel, :index?
    ensure_team_rooms
    channels = InternalChat::Channel.visible_to(Current.user, Current.account).to_a
    render json: { payload: channels.map { |channel| channel_json(channel, channels) } }
  end

  def create
    channel = build_channel
    authorize channel, :create?
    channel = persist(channel)
    render json: channel_json(channel, [channel])
  end

  def read
    authorize @channel, :read?
    @channel.participants.find_by!(user: Current.user).mark_read!
    render json: channel_json(@channel, [@channel])
  end

  private

  def fetch_channel
    @channel = InternalChat::Channel.where(account: Current.account).find(params[:id])
  end

  # The company room and the team rooms are created the first time a member lists their channels.
  def ensure_team_rooms
    InternalChat::Channel.find_or_create_company_room!(Current.account).ensure_participants!([Current.user])
    Current.user.teams.where(account: Current.account).find_each do |team|
      InternalChat::Channel.find_or_create_for_team!(Current.account, team).ensure_participants!([Current.user])
    end
  end

  def build_channel
    case params.require(:kind)
    when 'direct' then build_direct_channel
    when 'team_room' then build_team_channel
    else raise ActionController::ParameterMissing, 'kind must be direct or team_room'
    end
  end

  def build_direct_channel
    other = Current.account.users.find(params.require(:user_id))
    raise ActionController::ParameterMissing, 'user_id must be another agent' if other.id == Current.user.id

    InternalChat::Channel.new(account: Current.account, kind: :direct, direct_key: InternalChat::Channel.direct_key_for(Current.user.id, other.id))
  end

  def build_team_channel
    InternalChat::Channel.new(account: Current.account, kind: :team_room, team: Current.account.teams.find(params.require(:team_id)))
  end

  def persist(channel)
    if channel.direct?
      InternalChat::Channel.find_or_create_direct!(Current.account, *channel.members.to_a)
    else
      InternalChat::Channel.find_or_create_for_team!(Current.account, channel.team).tap { |room| room.ensure_participants!([Current.user]) }
    end
  end

  def last_messages_by_channel(channels)
    latest_ids = InternalChat::Message.where(channel_id: channels.map(&:id)).group(:channel_id).select('MAX(id)')
    InternalChat::Message.where(id: latest_ids).includes(:sender).index_by(&:channel_id)
  end

  def channel_json(channel, channels)
    @unread_counts ||= InternalChat::Channel.unread_counts_for(Current.user, channels.map(&:id))
    @last_messages ||= last_messages_by_channel(channels)
    channel.push_event_data_for(Current.user, unread_count: @unread_counts.fetch(channel.id, 0), last_message: @last_messages[channel.id],
                                              can_post: channel.can_post?(Current.account_user))
  end
end
