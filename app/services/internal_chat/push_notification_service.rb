# Push (browser and FCM) for internal chat messages. It reuses the delivery code of the conversation
# push service and replaces only what is tied to conversations: title, body, link and the payload sent
# to the mobile app. The user preference is the `push_internal_message` flag of NotificationSetting.
class InternalChat::PushNotificationService < Notification::PushNotificationService
  PUSH_TYPE = 'internal_message'.freeze
  BODY_LENGTH = 100

  # What the parent service reads from a Notification, so no Notification record is needed.
  Payload = Struct.new(:user, :account, :notification_type, :push_message_title, :push_message_body, :fcm_push_data)

  def initialize(message:, recipient:)
    @message = message
    super(notification: build_payload(recipient))
  end

  private

  attr_reader :message

  # EXTENSION POINT (urgent messages outside business hours): conversation pushes to the phone are
  # held back outside the inbox working hours (see Notification::PushNotificationService). Internal
  # chat pushes are not held back at all for now. When the owner defines the rule, decide it here,
  # e.g. allow only `message.help_request?` outside business hours.
  def mobile_push_allowed?
    true
  end

  def push_message
    { title: notification.push_message_title, tag: "internal_chat_#{message.channel_id}", url: push_url }
  end

  def push_url
    app_account_url(id: message.account_id)
  end

  def build_payload(recipient)
    sender_name = message.sender&.name.to_s
    key = message.help_request? ? 'internal_chat.push.help_request' : 'internal_chat.push.new_message'
    Payload.new(recipient, message.account, PUSH_TYPE, I18n.t(key, name: sender_name), message.content.truncate(BODY_LENGTH), fcm_push_data)
  end

  def fcm_push_data
    {
      notification_type: PUSH_TYPE,
      primary_actor_type: message.class.name,
      primary_actor_id: message.id,
      primary_actor: { id: message.id, channel_id: message.channel_id },
      account_id: message.account_id
    }
  end
end
