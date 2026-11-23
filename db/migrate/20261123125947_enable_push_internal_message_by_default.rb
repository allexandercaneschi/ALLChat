# ALLChat: the push preference for internal chat messages starts turned on for everyone.
# Each agent can still turn it off in Profile > Notifications.
class EnablePushInternalMessageByDefault < ActiveRecord::Migration[7.1]
  # flag_shih_tzu bit of push_internal_message (notification type 10 => 2^(10 - 1))
  PUSH_INTERNAL_MESSAGE_BIT = 512

  def up
    execute "UPDATE notification_settings SET push_flags = push_flags | #{PUSH_INTERNAL_MESSAGE_BIT}"
  end

  def down
    execute "UPDATE notification_settings SET push_flags = push_flags & ~#{PUSH_INTERNAL_MESSAGE_BIT}"
  end
end
