# ALLChat: runs the scheduled broadcasts that are due. last_run_on is saved
# before queueing so a broadcast never goes out twice on the same day.
class Broadcasts::ScheduleRunnerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    now = BroadcastMessage.local_now
    BroadcastMessage.active.includes(:broadcast_list, :account).find_each do |broadcast|
      next unless broadcast.due?(now)

      broadcast.update!(last_run_on: now.to_date, active: !broadcast.once?)
      Broadcasts::DeliveryService.new(account: broadcast.account, contacts: broadcast.recipients(now.to_date),
                                      options: broadcast.delivery_options).perform
    end
  end
end
