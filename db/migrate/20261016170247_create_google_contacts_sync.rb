class CreateGoogleContactsSync < ActiveRecord::Migration[7.1]
  def change
    create_connections
    create_links
  end

  private

  def create_connections
    create_table :google_contacts_connections do |t|
      t.bigint :account_id, null: false
      t.string :email
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.boolean :enabled, null: false, default: true
      t.boolean :dry_run, null: false, default: true
      t.string :contact_group_resource_name
      t.datetime :last_synced_at
      t.jsonb :last_sync_summary, null: false, default: {}
      t.text :last_error
      t.timestamps
    end
    add_index :google_contacts_connections, :account_id, unique: true
  end

  def create_links
    create_table :google_contact_links do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.string :resource_name
      t.string :phone_key, null: false
      t.string :google_hash
      t.string :chatwoot_hash
      t.timestamps
    end
    add_index :google_contact_links, [:account_id, :phone_key], unique: true
    add_index :google_contact_links, [:account_id, :contact_id]
  end
end
