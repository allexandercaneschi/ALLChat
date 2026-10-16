# == Schema Information
#
# Table name: google_contacts_connections
#
#  id                          :bigint           not null, primary key
#  access_token                :text
#  contact_group_resource_name :string
#  dry_run                     :boolean          default(TRUE), not null
#  email                       :string
#  enabled                     :boolean          default(TRUE), not null
#  expires_at                  :datetime
#  last_error                  :text
#  last_sync_summary           :jsonb            not null
#  last_synced_at              :datetime
#  refresh_token               :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#
# Indexes
#
#  index_google_contacts_connections_on_account_id  (account_id) UNIQUE
#

# ALLChat: the Google account whose contacts sync with this Chatwoot account.
class GoogleContactsConnection < ApplicationRecord
  belongs_to :account

  if Chatwoot.encryption_configured?
    encrypts :access_token
    encrypts :refresh_token
  end

  validates :account_id, uniqueness: true

  scope :active, -> { where(enabled: true).where.not(refresh_token: nil) }

  def as_json(*)
    {
      email: email,
      enabled: enabled,
      dry_run: dry_run,
      last_synced_at: last_synced_at&.to_i,
      last_sync_summary: last_sync_summary,
      last_error: last_error
    }
  end
end
