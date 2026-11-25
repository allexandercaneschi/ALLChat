# ALLChat: memory of the texts each contact's automatic responder sends (WhatsApp Business away
# message, chatbot menus), so the auto reply guard recognises them again without asking the LLM.
# A text marked as human (by the LLM or by an agent removing the label) is never held.
class CreateAutoReplySignatures < ActiveRecord::Migration[7.1]
  def change
    create_table :auto_reply_signatures do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.string :fingerprint, null: false
      t.text :sample
      t.integer :verdict, null: false, default: 0
      t.integer :source, null: false, default: 0
      t.integer :hits, null: false, default: 0
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :auto_reply_signatures, [:contact_id, :fingerprint], unique: true
    add_index :auto_reply_signatures, :account_id
  end
end
