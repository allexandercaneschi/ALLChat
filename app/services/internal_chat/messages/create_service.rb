# Creates a message in a channel, moves the sender's read pointer, broadcasts it to the members of the
# channel (and only to them) and queues the push notifications.
class InternalChat::Messages::CreateService
  MESSAGE_CREATED_EVENT = 'internal_chat.message.created'.freeze
  MESSAGE_UPDATED_EVENT = 'internal_chat.message.updated'.freeze

  # extra: kind (:text by default), recipient, conversation, urgent and mentioned_user_ids.
  def initialize(channel:, sender:, content: '', **extra)
    @channel = channel
    @sender = sender
    @mentioned_user_ids = Array(extra.delete(:mentioned_user_ids))
    @attributes = { account_id: channel.account_id, sender: sender, content: content, **extra }
  end

  def perform
    message = create_message
    self.class.broadcast(message, MESSAGE_CREATED_EVENT)
    notify_members(message)
    message
  end

  # Only the pubsub tokens of the channel members are used, never the account-wide stream.
  def self.broadcast(message, event)
    tokens = message.channel.members.pluck(:pubsub_token)
    ActionCableBroadcastJob.perform_later(tokens, event, message.push_event_data.merge(account_id: message.account_id))
  end

  private

  attr_reader :channel, :sender

  def create_message
    InternalChat::Message.transaction do
      # Pointers start at the current end of the conversation, so only this message counts as unread for the others.
      channel.ensure_participants!
      ensure_nudge_allowed! if @attributes[:kind].to_s == 'nudge'
      message = channel.messages.create!(@attributes.merge(mentioned_user_ids: mentioned_member_ids))
      channel.participants.find_by!(user: sender).mark_read!(message.id)
      message
    end
  end

  def mentioned_member_ids
    channel.members.where(id: @mentioned_user_ids).where.not(id: sender.id).pluck(:id)
  end

  # The channel row is locked so two quick clicks cannot both pass the cooldown check.
  def ensure_nudge_allowed!
    channel.lock!
    last_nudge_at = channel.messages.nudge.where(sender: sender).maximum(:created_at)
    return if last_nudge_at.blank? || last_nudge_at <= InternalChat::NUDGE_COOLDOWN.ago

    raise CustomExceptions::InternalChat::NudgeTooSoon.new(retry_after: (last_nudge_at + InternalChat::NUDGE_COOLDOWN - Time.current).ceil)
  end

  def notify_members(message)
    channel.members.where.not(id: sender.id).pluck(:id).each do |user_id|
      InternalChat::PushNotificationJob.perform_later(message.id, user_id)
    end
  end
end
