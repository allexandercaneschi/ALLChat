# ALLChat: internal team chat. Everything lives under this namespace (tables, models, policies,
# services) so upstream Chatwoot updates do not collide with it.
module InternalChat
  DEFAULT_RETENTION_DAYS = 365
  MAX_MESSAGE_LENGTH = 5000
  # Minimum time between two attention nudges of the same person in the same conversation.
  NUDGE_COOLDOWN = 60.seconds

  def self.table_name_prefix
    'internal_chat_'
  end

  # Days to keep messages, configurable per account (account settings: internal_chat_retention_days).
  def self.retention_days(account)
    account.settings['internal_chat_retention_days'].presence&.to_i || DEFAULT_RETENTION_DAYS
  end

  # Days to keep resolved customer conversations (account settings: conversation_retention_days).
  def self.conversation_retention_days(account)
    account.settings['conversation_retention_days'].presence&.to_i || DEFAULT_RETENTION_DAYS
  end

  # Nothing is deleted unless the account turned the cleanup on (account settings: retention_cleanup_enabled).
  def self.retention_cleanup_enabled?(account)
    account.settings['retention_cleanup_enabled'] == true
  end
end
