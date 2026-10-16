class CreateConversationRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_requests do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :requester_id, null: false
      t.bigint :target_id, null: false
      t.integer :request_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.timestamps
    end

    add_index :conversation_requests, [:conversation_id, :status]
    add_index :conversation_requests, [:target_id, :status]
    add_index :conversation_requests, [:requester_id, :status]
    add_index :conversation_requests, [:status, :expires_at]
  end
end
