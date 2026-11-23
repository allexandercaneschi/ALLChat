# ALLChat: internal chat urgency (mentions, urgent flag, attention nudge), claimable help requests,
# message search index and the audit access log.
class AddUrgencyHelpAndAuditToInternalChat < ActiveRecord::Migration[7.1]
  def change
    change_table :internal_chat_messages, bulk: true do |t|
      t.boolean :urgent, null: false, default: false
      t.bigint :mentioned_user_ids, array: true, null: false, default: []
      t.bigint :claimed_by_id
      t.datetime :claimed_at
      t.datetime :resolved_at
    end
    add_index :internal_chat_messages, :content, using: :gin, opclass: :gin_trgm_ops, name: 'index_internal_chat_messages_on_content_trgm'

    create_table :internal_chat_audit_logs do |t|
      t.bigint :account_id, null: false
      t.bigint :auditor_id, null: false
      t.bigint :channel_id, null: false
      t.string :action, null: false
      t.datetime :created_at, null: false
    end
    add_index :internal_chat_audit_logs, [:account_id, :created_at]
    add_index :internal_chat_audit_logs, :channel_id
  end
end
