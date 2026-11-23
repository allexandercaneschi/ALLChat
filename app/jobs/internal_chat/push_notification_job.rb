class InternalChat::PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(message_id, user_id)
    message = InternalChat::Message.find_by(id: message_id)
    recipient = User.find_by(id: user_id)
    return if message.blank? || recipient.blank?

    InternalChat::PushNotificationService.new(message: message, recipient: recipient).perform
  end
end
