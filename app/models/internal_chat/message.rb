# == Schema Information
#
# Table name: internal_chat_messages
#
#  id              :bigint           not null, primary key
#  content         :text             not null
#  kind            :integer          default("text"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  channel_id      :bigint           not null
#  conversation_id :bigint
#  recipient_id    :bigint
#  sender_id       :bigint           not null
#
# Indexes
#
#  index_internal_chat_messages_on_channel_id_and_id  (channel_id,id)
#  index_internal_chat_messages_on_created_at         (created_at)
#

# A text message. `help_request` messages are addressed to ONE person (`recipient`) and can only
# live in a direct channel, so they can never reach a team or the whole account.
class InternalChat::Message < ApplicationRecord
  belongs_to :account
  belongs_to :channel, class_name: 'InternalChat::Channel'
  belongs_to :sender, class_name: 'User'
  belongs_to :recipient, class_name: 'User', optional: true
  belongs_to :conversation, optional: true

  enum kind: { text: 0, help_request: 1 }

  validates :content, presence: true, length: { maximum: InternalChat::MAX_MESSAGE_LENGTH }
  validate :sender_belongs_to_channel
  validate :help_request_is_addressed_to_one_person
  validate :conversation_belongs_to_account

  # Messages past the account retention period. Used by a future cleanup, nothing deletes them today.
  scope :past_retention, ->(account) { where(account: account).where(created_at: ...InternalChat.retention_days(account).days.ago) }

  def push_event_data
    {
      id: id,
      channel_id: channel_id,
      kind: kind,
      content: content,
      sender: sender&.push_event_data,
      recipient_id: recipient_id,
      conversation_id: conversation_id,
      created_at: created_at.to_i
    }
  end

  private

  def sender_belongs_to_channel
    errors.add(:sender, 'is not part of the channel') if channel && !channel.member?(sender)
  end

  def conversation_belongs_to_account
    errors.add(:conversation, 'must belong to the account') if conversation && conversation.account_id != account_id
  end

  def help_request_is_addressed_to_one_person
    return unless help_request?

    errors.add(:channel, 'must be a direct channel') unless channel&.direct?
    errors.add(:recipient, 'must be the other person in the channel') unless other_person_in_channel?(recipient)
  end

  def other_person_in_channel?(user)
    user.present? && user != sender && channel&.member?(user)
  end
end
