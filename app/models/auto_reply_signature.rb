# == Schema Information
#
# Table name: auto_reply_signatures
#
#  id           :bigint           not null, primary key
#  fingerprint  :string           not null
#  hits         :integer          default(0), not null
#  last_seen_at :datetime
#  sample       :text
#  source       :integer          default("rule"), not null
#  verdict      :integer          default("auto_reply"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  contact_id   :bigint           not null
#
# Indexes
#
#  index_auto_reply_signatures_on_account_id                  (account_id)
#  index_auto_reply_signatures_on_contact_id_and_fingerprint  (contact_id,fingerprint) UNIQUE
#

# ALLChat: what the auto reply guard learned about a text a contact sends. The text is normalised
# (no accents, digits, links or punctuation) so "Olá! Retornamos às 08:00 do dia 25/11" and the same
# message on another day share the fingerprint. See AutoReply::Guard.
class AutoReplySignature < ApplicationRecord
  # Short texts ("ok", "obrigado") are too common to be remembered as automatic.
  MIN_NORMALIZED_LENGTH = 15
  SAMPLE_LIMIT = 500

  belongs_to :account
  belongs_to :contact

  enum verdict: { auto_reply: 0, human: 1 }
  enum source: { rule: 0, ai: 1, agent: 2 }

  validates :fingerprint, presence: true, uniqueness: { scope: :contact_id }

  class << self
    def normalize(text)
      I18n.transliterate(text.to_s.downcase, replacement: ' ')
          .gsub(%r{https?://\S+|www\.\S+}, ' ')
          .gsub(/[^a-z]+/, ' ')
          .squish
    end

    def fingerprint_for(text)
      normalized = normalize(text)
      return if normalized.length < MIN_NORMALIZED_LENGTH

      Digest::SHA256.hexdigest(normalized)
    end

    def lookup(contact, text)
      fingerprint = fingerprint_for(text)
      return if fingerprint.blank?

      find_by(contact_id: contact.id, fingerprint: fingerprint)
    end

    # Records (or corrects) what a text is. An agent's correction always wins; the LLM and the
    # rules never overwrite it.
    def remember!(contact, text, verdict:, source:)
      fingerprint = fingerprint_for(text)
      return if fingerprint.blank?

      signature = find_or_initialize_by(contact_id: contact.id, fingerprint: fingerprint) do |record|
        record.account_id = contact.account_id
      end
      return signature if signature.persisted? && signature.agent? && source.to_s != 'agent'

      signature.update!(verdict: verdict, source: source, sample: text.to_s.truncate(SAMPLE_LIMIT), last_seen_at: Time.current)
      signature
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end

  def seen!
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(hits: hits + 1, last_seen_at: Time.current, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
