# Business hours of an agent. ALLChat only has working hours per inbox, so an agent is out of hours when
# every inbox they belong to that has working hours turned on is closed (or on a break) right now.
# An agent without any inbox with working hours is never considered out of hours.
class InternalChat::Availability
  def self.out_of_hours?(user, account)
    inboxes = user.inboxes.where(account: account, working_hours_enabled: true).to_a
    inboxes.any? && inboxes.all?(&:out_of_office?)
  end
end
