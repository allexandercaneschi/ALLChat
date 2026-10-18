# == Schema Information
#
# Table name: google_contact_links
#
#  id            :bigint           not null, primary key
#  chatwoot_changed_at :datetime
#  chatwoot_hash :string
#  google_hash   :string
#  phone_key     :string           not null
#  resource_name :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  contact_id    :bigint
#
# Indexes
#
#  index_google_contact_links_on_account_id_and_contact_id  (account_id,contact_id)
#  index_google_contact_links_on_account_id_and_phone_key   (account_id,phone_key) UNIQUE
#

# ALLChat: a Chatwoot contact and a Google contact that share a phone, with the
# fingerprint of both sides at the last sync to tell which side changed.
class GoogleContactLink < ApplicationRecord
  belongs_to :account

  validates :phone_key, presence: true, uniqueness: { scope: :account_id }
end
