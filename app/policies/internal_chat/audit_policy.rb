# Audit of internal conversations: administrators read everything and each supervisor reads the
# conversations of their teams (see InternalChat::Channel.auditable_by).
class InternalChat::AuditPolicy < ApplicationPolicy
  def index?
    account_user&.administrator_or_supervisor? || false
  end

  def show?
    index? && InternalChat::Channel.auditable_by(user, account_user, account).exists?(id: record.id)
  end
end
