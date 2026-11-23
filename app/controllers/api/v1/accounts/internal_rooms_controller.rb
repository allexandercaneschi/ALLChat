# ALLChat: settings of the internal chat rooms (the company room and the room of each team).
# Only administrators. Today it sets who can send messages: everyone, only administrators, or
# administrators and supervisors.
class Api::V1::Accounts::InternalRoomsController < Api::V1::Accounts::BaseController
  def index
    authorize InternalChat::Channel, policy_class: InternalChat::RoomPolicy
    render json: { payload: rooms.map { |room| room_json(room) } }
  end

  def update
    authorize InternalChat::Channel, policy_class: InternalChat::RoomPolicy
    room = rooms.find { |candidate| candidate.id == params[:id].to_i }
    raise ActiveRecord::RecordNotFound unless room

    room.update!(posting_policy: posting_policy)
    render json: room_json(room)
  end

  private

  # Rooms that do not exist yet are created, so they can be configured before anyone opens them.
  def rooms
    @rooms ||= begin
      company = InternalChat::Channel.find_or_create_company_room!(Current.account)
      team_rooms = Current.account.teams.map { |team| InternalChat::Channel.find_or_create_for_team!(Current.account, team) }
      [company] + team_rooms
    end
  end

  def posting_policy
    value = params.require(:posting_policy)
    raise ActionController::ParameterMissing, "posting_policy must be one of #{InternalChat::Channel.posting_policies.keys.join(', ')}" unless
      InternalChat::Channel.posting_policies.key?(value)

    value
  end

  def room_json(room)
    {
      id: room.id,
      kind: room.kind,
      name: room.company_room? ? Current.account.name : room.team.name,
      team_id: room.team_id,
      posting_policy: room.posting_policy,
      members_count: room.members.count
    }
  end
end
