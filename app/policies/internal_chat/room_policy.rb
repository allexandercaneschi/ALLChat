# Settings of the rooms (who can send messages). Only administrators.
class InternalChat::RoomPolicy < ApplicationPolicy
  def index?
    account_user&.administrator? || false
  end

  def update?
    index?
  end
end
