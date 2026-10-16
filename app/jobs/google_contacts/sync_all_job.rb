# ALLChat: hourly Google Contacts sync for every connected account.
class GoogleContacts::SyncAllJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    GoogleContactsConnection.active.find_each { |connection| GoogleContacts::SyncJob.perform_later(connection) }
  end
end
