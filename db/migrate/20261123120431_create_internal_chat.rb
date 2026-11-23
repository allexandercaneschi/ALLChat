# ALLChat: internal team chat (direct conversations between agents and team rooms).
class CreateInternalChat < ActiveRecord::Migration[7.1]
  def change
    create_channels
    create_participants
    create_messages
  end

  private

  def create_channels
    create_table :internal_chat_channels do |t|
      t.bigint :account_id, null: false
      t.integer :kind, null: false, default: 0
      t.bigint :team_id
      # "<lower user id>:<higher user id>" so a pair of agents has a single direct channel
      t.string :direct_key
      t.timestamps
    end
    add_index :internal_chat_channels, [:account_id, :direct_key], unique: true, where: 'direct_key IS NOT NULL',
                                                                   name: 'index_internal_chat_channels_on_account_and_direct_key'
    add_index :internal_chat_channels, [:account_id, :team_id], unique: true, where: 'team_id IS NOT NULL',
                                                                name: 'index_internal_chat_channels_on_account_and_team'
  end

  def create_participants
    create_table :internal_chat_participants do |t|
      t.bigint :channel_id, null: false
      t.bigint :user_id, null: false
      t.bigint :last_read_message_id, null: false, default: 0
      t.timestamps
    end
    add_index :internal_chat_participants, [:channel_id, :user_id], unique: true
    add_index :internal_chat_participants, :user_id
  end

  def create_messages
    create_table :internal_chat_messages do |t|
      t.bigint :account_id, null: false
      t.bigint :channel_id, null: false
      t.bigint :sender_id, null: false
      # Set only on help requests: the one person the request is addressed to.
      t.bigint :recipient_id
      t.bigint :conversation_id
      t.integer :kind, null: false, default: 0
      t.text :content, null: false
      t.timestamps
    end
    add_index :internal_chat_messages, [:channel_id, :id]
    add_index :internal_chat_messages, :created_at
  end
end
