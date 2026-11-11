class CreateBroadcastLists < ActiveRecord::Migration[7.1]
  def change
    create_table :broadcast_lists do |t|
      t.bigint :account_id, null: false
      t.bigint :label_id, null: false
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    add_index :broadcast_lists, [:account_id, :name], unique: true
    add_index :broadcast_lists, :label_id, unique: true

    create_table :broadcast_list_users do |t|
      t.bigint :broadcast_list_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end

    add_index :broadcast_list_users, [:broadcast_list_id, :user_id], unique: true
    add_index :broadcast_list_users, :user_id
  end
end
