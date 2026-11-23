# Direct channels belong to their two participants and team rooms to the members of the team.
# Administrators have no extra access to either.
class InternalChat::ChannelPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def create?
    index? && record.account_id == account.id && record.member?(user)
  end

  def show?
    create?
  end

  def read?
    show?
  end
end
