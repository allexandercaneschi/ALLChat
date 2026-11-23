# == Schema Information
#
# Table name: internal_chat_participants
#
#  id                   :bigint           not null, primary key
#  last_read_message_id :bigint           default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  channel_id           :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_internal_chat_participants_on_channel_id_and_user_id  (channel_id,user_id) UNIQUE
#  index_internal_chat_participants_on_user_id                 (user_id)
#

# Per-user read pointer of a channel. Unread messages are the ones after `last_read_message_id`.
class InternalChat::Participant < ApplicationRecord
  belongs_to :channel, class_name: 'InternalChat::Channel'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :channel_id }

  def mark_read!(message_id = channel.messages.maximum(:id))
    return if message_id.blank? || message_id <= last_read_message_id

    update!(last_read_message_id: message_id)
  end
end
