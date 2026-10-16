# ALLChat: syncs one account with its Google contacts.
class GoogleContacts::SyncJob < ApplicationJob
  queue_as :low

  def perform(connection)
    return unless connection.enabled? && connection.refresh_token.present?

    GoogleContacts::SyncService.new(connection).perform
  end
end
