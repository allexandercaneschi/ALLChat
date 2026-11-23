# Creates a message in a channel, moves the sender's read pointer, broadcasts it to the members of the
# channel (and only to them) and queues the push notifications.
class InternalChat::Messages::CreateService
  MESSAGE_CREATED_EVENT = 'internal_chat.message.created'.freeze

  # extra: kind (:text by default), recipient and conversation, used by help requests.
  def initialize(channel:, sender:, content:, **extra)
    @channel = channel
    @sender = sender
    @attributes = { account_id: channel.account_id, sender: sender, content: content, **extra }
  end

  def perform
    message = create_message
    broadcast(message)
    notify_members(message)
    message
  end

  private

  attr_reader :channel, :sender

  def create_message
    InternalChat::Message.transaction do
      # Pointers start at the current end of the conversation, so only this message counts as unread for the others.
      channel.ensure_participants!
      message = channel.messages.create!(@attributes)
      channel.participants.find_by!(user: sender).mark_read!(message.id)
      message
    end
  end

  # Only the pubsub tokens of the channel members are used, never the account-wide stream.
  def broadcast(message)
    tokens = channel.members.pluck(:pubsub_token)
    ActionCableBroadcastJob.perform_later(tokens, MESSAGE_CREATED_EVENT, message.push_event_data.merge(account_id: channel.account_id))
  end

  def notify_members(message)
    channel.members.where.not(id: sender.id).pluck(:id).each do |user_id|
      InternalChat::PushNotificationJob.perform_later(message.id, user_id)
    end
  end
end
