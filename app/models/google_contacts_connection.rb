# == Schema Information
#
# Table name: google_contacts_connections
#
#  id                          :bigint           not null, primary key
#  access_token                :text
#  conflict_overrides          :jsonb            not null
#  conflict_winner             :string           default("google"), not null
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

  CONFLICT_WINNERS = %w[google chatwoot newest].freeze
  CONTACT_CHOICES = %w[google chatwoot].freeze

  validates :account_id, uniqueness: true
  validates :conflict_winner, inclusion: { in: CONFLICT_WINNERS }
  validate :conflict_overrides_are_choices

  scope :active, -> { where(enabled: true).where.not(refresh_token: nil) }

  def as_json(*)
    {
      email: email,
      enabled: enabled,
      dry_run: dry_run,
      conflict_winner: conflict_winner,
      conflict_overrides: conflict_overrides,
      last_synced_at: last_synced_at&.to_i,
      last_sync_summary: last_sync_summary,
      last_error: last_error
    }
  end

  private

  def conflict_overrides_are_choices
    return if conflict_overrides.is_a?(Hash) && conflict_overrides.values.all? { |value| CONTACT_CHOICES.include?(value) }

    errors.add(:conflict_overrides, :invalid)
  end
end
