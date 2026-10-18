# ALLChat: syncs one account with its Google contacts.
class GoogleContacts::SyncJob < ApplicationJob
  queue_as :low

  # apply: write this run even when the connection is in dry run.
  def perform(connection, apply: false)
    return if connection.refresh_token.blank?
    return unless connection.enabled? || apply

    GoogleContacts::SyncService.new(connection, apply: apply).perform
  end
end
