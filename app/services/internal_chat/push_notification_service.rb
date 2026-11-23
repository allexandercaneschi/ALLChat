# Push (browser and FCM) for internal chat messages. It reuses the delivery code of the conversation
# push service and replaces only what is tied to conversations: title, body, link and the payload sent
# to the mobile app. The user preference is the `push_internal_message` flag of NotificationSetting.
#
# Out of business hours (see InternalChat::Availability) nothing is pushed, except urgent messages:
# an @mention, a message marked as urgent in a direct conversation and the attention nudge.
class InternalChat::PushNotificationService < Notification::PushNotificationService
  PUSH_TYPE = 'internal_message'.freeze
  BODY_LENGTH = 100

  # What the parent service reads from a Notification, so no Notification record is needed.
  Payload = Struct.new(:user, :account, :notification_type, :push_message_title, :push_message_body, :fcm_push_data)

  def initialize(message:, recipient:)
    @message = message
    @recipient = recipient
    super(notification: build_payload)
  end

  def perform
    return unless urgent? || !InternalChat::Availability.out_of_hours?(@recipient, message.account)

    super
  end

  def urgent?
    message.nudge? || message.urgent || message.mentioned_user_ids.include?(@recipient.id)
  end

  private

  attr_reader :message

  # Urgent pushes must not be held back and must call attention on the phone.
  def mobile_push_allowed?
    true
  end

  def push_message
    { title: notification.push_message_title, tag: "internal_chat_#{message.channel_id}", url: push_url, urgent: urgent? }
  end

  def push_url
    app_account_url(id: message.account_id)
  end

  def fcm_android_options
    return super unless urgent?

    { priority: 'high', notification: { channel_id: 'urgent', sound: 'urgent' } }
  end

  def fcm_apns_options
    return super unless urgent?

    { payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive', category: Time.zone.now.to_i.to_s } } }
  end

  def title_key
    return 'internal_chat.push.nudge' if message.nudge?
    return 'internal_chat.push.mention' if !message.help_request? && message.mentioned_user_ids.include?(@recipient.id)
    return 'internal_chat.push.help_request' if message.help_request? && message.recipient_id.present?
    return 'internal_chat.push.help_request_team' if message.help_request?

    'internal_chat.push.new_message'
  end

  def build_payload
    name = message.sender&.name.to_s
    Payload.new(@recipient, message.account, PUSH_TYPE, I18n.t(title_key, name: name), message.content.truncate(BODY_LENGTH), fcm_push_data)
  end

  def fcm_push_data
    {
      notification_type: PUSH_TYPE,
      primary_actor_type: message.class.name,
      primary_actor_id: message.id,
      primary_actor: { id: message.id, channel_id: message.channel_id },
      urgent: urgent?,
      account_id: message.account_id
    }
  end
end
