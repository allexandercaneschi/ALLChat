# == Schema Information
#
# Table name: internal_chat_messages
#
#  id                 :bigint           not null, primary key
#  claimed_at        :datetime
#  content           :text             not null
#  kind              :integer          default("text"), not null
#  mentioned_user_ids :bigint          default([]), not null, is an Array
#  resolved_at       :datetime
#  urgent            :boolean          default(FALSE), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  channel_id        :bigint           not null
#  claimed_by_id     :bigint
#  conversation_id   :bigint
#  recipient_id      :bigint
#  sender_id         :bigint           not null
#
# Indexes
#
#  index_internal_chat_messages_on_channel_id_and_id  (channel_id,id)
#  index_internal_chat_messages_on_content_trgm       (content) USING gin
#  index_internal_chat_messages_on_created_at         (created_at)
#

# A message of an internal channel.
# - text: normal message. It can be marked `urgent` (direct channels only) and can mention members.
# - help_request: asks for help. Addressed to ONE person in a direct channel or to the whole team in a
#   team room. Whoever knows how to help claims it (first one wins) and the request can then be resolved.
# - nudge: "call attention" button. Direct channels only, with a cooldown between uses.
class InternalChat::Message < ApplicationRecord
  belongs_to :account
  belongs_to :channel, class_name: 'InternalChat::Channel'
  belongs_to :sender, class_name: 'User'
  belongs_to :recipient, class_name: 'User', optional: true
  belongs_to :claimed_by, class_name: 'User', optional: true
  belongs_to :conversation, optional: true

  enum kind: { text: 0, help_request: 1, nudge: 2 }

  validates :content, presence: true, length: { maximum: InternalChat::MAX_MESSAGE_LENGTH }, unless: :nudge?
  validate :sender_belongs_to_channel
  validate :help_request_has_a_valid_audience
  validate :direct_only_features
  validate :conversation_belongs_to_account

  # Messages past the account retention period.
  scope :past_retention, ->(account) { where(account: account).where(created_at: ...InternalChat.retention_days(account).days.ago) }
  scope :open_help_requests, -> { help_request.where(claimed_by_id: nil, resolved_at: nil) }

  # Takes the help request. Only the first person wins: the update is a single conditional statement.
  def claim!(user)
    raise CustomExceptions::InternalChat::NotAHelpRequest.new({}) unless help_request?

    claimed = self.class.where(id: id, claimed_by_id: nil).update_all(claimed_by_id: user.id, claimed_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    raise CustomExceptions::InternalChat::AlreadyClaimed.new({}) if claimed.zero?

    reload
  end

  def resolve!
    raise CustomExceptions::InternalChat::NotAHelpRequest.new({}) unless help_request?

    update!(resolved_at: Time.current)
  end

  def claimed?
    claimed_by_id.present?
  end

  def push_event_data
    {
      id: id,
      channel_id: channel_id,
      kind: kind,
      content: content,
      urgent: urgent,
      mentioned_user_ids: mentioned_user_ids,
      sender: sender&.push_event_data,
      recipient_id: recipient_id,
      conversation_id: conversation_id,
      claimed_by: claimed_by&.push_event_data,
      claimed_at: claimed_at&.to_i,
      resolved_at: resolved_at&.to_i,
      created_at: created_at.to_i
    }
  end

  private

  def sender_belongs_to_channel
    errors.add(:sender, 'is not part of the channel') if channel && !channel.member?(sender)
  end

  # To one person (direct channel) or to the whole team (team room), never to the whole account.
  def help_request_has_a_valid_audience
    return unless help_request?

    if channel&.direct?
      errors.add(:recipient, 'must be the other person in the channel') unless other_person_in_channel?(recipient)
    elsif recipient.present?
      errors.add(:recipient, 'must be empty in a team room')
    end
  end

  def direct_only_features
    return if channel.blank? || channel.direct?

    errors.add(:channel, 'must be a direct channel') if nudge? || urgent
  end

  def other_person_in_channel?(user)
    user.present? && user != sender && channel&.member?(user)
  end

  def conversation_belongs_to_account
    errors.add(:conversation, 'must belong to the account') if conversation && conversation.account_id != account_id
  end
end
