class InternalChat::MessagePolicy < ApplicationPolicy
  def index?
    InternalChat::ChannelPolicy.new(user_context, record.channel).show?
  end

  def create?
    index?
  end
end
