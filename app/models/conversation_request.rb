# == Schema Information
#
# Table name: conversation_requests
#
#  id              :bigint           not null, primary key
#  expires_at      :datetime         not null
#  request_type    :integer          default("transfer"), not null
#  responded_at    :datetime
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  requester_id    :bigint           not null
#  target_id       :bigint           not null
#
# Indexes
#
#  index_conversation_requests_on_conversation_id_and_status  (conversation_id,status)
#  index_conversation_requests_on_requester_id_and_status     (requester_id,status)
#  index_conversation_requests_on_status_and_expires_at       (status,expires_at)
#  index_conversation_requests_on_target_id_and_status        (target_id,status)
#

# ALLChat: a request that another agent must accept.
# - transfer: the assignee (requester) hands the conversation to target.
# - participation: requester asks the assignee (target) to reply in the conversation.
class ConversationRequest < ApplicationRecord
  DEFAULT_TIMEOUT_MINUTES = 60
  EVENT_NAME = 'conversation_request.updated'.freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :requester, class_name: 'User'
  belongs_to :target, class_name: 'User'

  enum request_type: { transfer: 0, participation: 1 }
  enum status: { pending: 0, accepted: 1, declined: 2, expired: 3, cancelled: 4 }

  validates :expires_at, presence: true
  validate :target_differs_from_requester, on: :create
  validate :single_pending_request, on: :create

  before_validation :set_defaults, on: :create
  after_commit :broadcast_update

  scope :open_requests, -> { pending.where('expires_at > ?', Time.current) }
  scope :involving, ->(user) { where(requester: user).or(where(target: user)) }

  def self.timeout_for(account)
    account.conversation_request_timeout.presence&.to_i || DEFAULT_TIMEOUT_MINUTES
  end

  def open?
    pending? && expires_at.future?
  end

  def accept!
    transaction do
      locked_conversation = Conversation.lock.find(conversation_id)
      lock!
      raise CustomExceptions::ConversationRequest::NotOpen.new({}) unless open?
      raise CustomExceptions::ConversationRequest::Stale.new({}) if locked_conversation.assignee_id != owner_id

      transfer? ? hand_over(locked_conversation) : add_participant(locked_conversation)
      update!(status: :accepted, responded_at: Time.current)
    end
  end

  def decline!
    close!(:declined)
  end

  def cancel!
    close!(:cancelled)
  end

  def expire!
    close!(:expired)
  end

  def push_event_data
    {
      id: id,
      request_type: request_type,
      status: status,
      expires_at: expires_at.to_i,
      created_at: created_at.to_i,
      conversation_id: conversation.display_id,
      inbox_id: conversation.inbox_id,
      contact_name: conversation.contact&.name,
      requester: requester.push_event_data,
      target: target.push_event_data
    }
  end

  private

  # The agent who owns the conversation when the request is created.
  def owner_id
    transfer? ? requester_id : target_id
  end

  def hand_over(locked_conversation)
    Conversations::AssignmentService.new(conversation: locked_conversation, assignee_id: target_id).perform
  end

  def add_participant(locked_conversation)
    locked_conversation.conversation_participants.find_or_create_by!(user_id: requester_id)
  end

  def close!(new_status)
    transaction do
      lock!
      raise CustomExceptions::ConversationRequest::NotOpen.new({}) unless pending?

      update!(status: new_status, responded_at: Time.current)
    end
  end

  def set_defaults
    self.account_id ||= conversation&.account_id
    self.expires_at ||= self.class.timeout_for(conversation.account).minutes.from_now if conversation
  end

  def target_differs_from_requester
    errors.add(:target, 'must be another agent') if target_id == requester_id
  end

  def single_pending_request
    return unless self.class.open_requests.exists?(conversation_id: conversation_id, requester_id: requester_id, request_type: request_type)

    errors.add(:base, I18n.t('conversations.requests.already_pending'))
  end

  def broadcast_update
    tokens = [requester&.pubsub_token, target&.pubsub_token].compact
    ActionCableBroadcastJob.perform_later(tokens, EVENT_NAME, push_event_data.merge(account_id: account_id))
  end
end
