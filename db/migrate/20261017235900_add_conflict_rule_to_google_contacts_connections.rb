class AddConflictRuleToGoogleContactsConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :google_contacts_connections, :conflict_winner, :string, null: false, default: 'google'
    add_column :google_contacts_connections, :conflict_overrides, :jsonb, null: false, default: {}
    add_column :google_contact_links, :chatwoot_changed_at, :datetime
  end
end
