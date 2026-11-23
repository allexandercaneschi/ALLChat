# ALLChat: who can send messages in a room (everyone, only administrators, administrators and
# supervisors) and a single company-wide room per account.
class AddPostingPolicyAndCompanyRoomToInternalChat < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_chat_channels, :posting_policy, :integer, null: false, default: 0
    add_index :internal_chat_channels, :account_id, unique: true, where: 'kind = 2',
                                                    name: 'index_internal_chat_channels_company_room_per_account'
  end
end
