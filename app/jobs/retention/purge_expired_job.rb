# ALLChat: removes what is past the retention period, but ONLY for accounts that turned the cleanup on
# (account setting `retention_cleanup_enabled`, off by default). Deleting is irreversible, so run
# `rails retention:report` first to see what would be removed.
#
# - internal chat messages older than `internal_chat_retention_days` (365 by default);
# - resolved customer conversations with no activity for `conversation_retention_days` (365 by default).
class Retention::PurgeExpiredJob < ApplicationJob
  queue_as :low
  BATCH_SIZE = 500

  def perform
    Account.find_each do |account|
      next unless InternalChat.retention_cleanup_enabled?(account)

      purge_internal_messages(account)
      purge_conversations(account)
    end
  end

  # What a run would remove for one account, without removing anything.
  def self.report(account)
    {
      internal_chat_messages: InternalChat::Message.past_retention(account).count,
      conversations: expired_conversations(account).count
    }
  end

  def self.expired_conversations(account)
    account.conversations.resolved.where(last_activity_at: ...InternalChat.conversation_retention_days(account).days.ago)
  end

  private

  def purge_internal_messages(account)
    InternalChat::Message.past_retention(account).in_batches(of: BATCH_SIZE).delete_all
  end

  def purge_conversations(account)
    self.class.expired_conversations(account).find_each(batch_size: BATCH_SIZE, &:destroy!)
  end
end
