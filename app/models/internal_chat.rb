# ALLChat: internal team chat. Everything lives under this namespace (tables, models, policies,
# services) so upstream Chatwoot updates do not collide with it.
module InternalChat
  DEFAULT_RETENTION_DAYS = 90
  MAX_MESSAGE_LENGTH = 5000

  def self.table_name_prefix
    'internal_chat_'
  end

  # Days to keep messages, configurable per account (account settings: internal_chat_retention_days).
  # Nothing is deleted yet: this only defines which messages a future cleanup job would remove.
  def self.retention_days(account)
    account.settings['internal_chat_retention_days'].presence&.to_i || DEFAULT_RETENTION_DAYS
  end
end
