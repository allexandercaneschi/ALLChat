# ALLChat: remembers when a contact's name or email changed, so the Google
# Contacts sync can tell which side changed last ("newest" conflict rule).
# The sync clears the mark once both sides match again.
module GoogleContactChangeTracking
  extend ActiveSupport::Concern

  included do
    after_update_commit :mark_google_contact_link_changed, if: -> { saved_change_to_name? || saved_change_to_email? }
  end

  private

  def mark_google_contact_link_changed
    GoogleContactLink.where(account_id: account_id, contact_id: id).update_all(chatwoot_changed_at: Time.current)
  end
end
