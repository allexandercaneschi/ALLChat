# == Schema Information
#
# Table name: broadcast_list_users
#
#  id                :bigint           not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  broadcast_list_id :bigint           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_broadcast_list_users_on_broadcast_list_id_and_user_id  (broadcast_list_id,user_id) UNIQUE
#  index_broadcast_list_users_on_user_id                        (user_id)
#

# ALLChat: a user authorized to use a broadcast list.
class BroadcastListUser < ApplicationRecord
  belongs_to :broadcast_list
  belongs_to :user

  validates :user_id, uniqueness: { scope: :broadcast_list_id }
end
