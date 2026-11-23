class InternalChat::MessagePolicy < ApplicationPolicy
  def index?
    InternalChat::ChannelPolicy.new(user_context, record.channel).show?
  end

  # A member sends messages unless the posting policy of the room restricts it.
  def create?
    index? && record.channel.can_post?(account_user)
  end

  # Anyone in the channel except who asked can take a help request.
  def claim?
    index? && record.sender_id != user.id
  end

  def resolve?
    index? && [record.sender_id, record.claimed_by_id].include?(user.id)
  end
end
