class CreateBroadcastMessages < ActiveRecord::Migration[7.1]
  CONTACT_ATTRIBUTES = [
    ['codigo_erp', 'Código ERP', 0, 'Código do cliente no ERP AML (CADCLI)'],
    ['data_nascimento', 'Data de nascimento', 5, 'Usada pela transmissão de aniversário'],
    ['empresa', 'Empresa (não usar nome)', 7, 'Marque para as transmissões usarem o texto padrão no lugar do primeiro nome']
  ].freeze

  def up
    create_table :broadcast_messages do |t|
      t.bigint :account_id, null: false
      t.bigint :broadcast_list_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :team_id
      t.bigint :created_by_id
      t.string :name, null: false
      t.text :content, null: false
      t.integer :schedule_kind, null: false, default: 0
      t.datetime :run_at
      t.integer :month
      t.integer :day
      t.integer :weekday
      t.integer :week_of_month
      t.string :send_time, null: false, default: '09:00'
      t.boolean :send_email, null: false, default: false
      t.string :name_fallback, null: false, default: 'cliente'
      t.integer :resolve_after_hours, null: false, default: 24
      t.boolean :active, null: false, default: true
      t.date :last_run_on
      t.timestamps
    end

    add_index :broadcast_messages, :account_id
    add_index :broadcast_messages, :broadcast_list_id

    seed_contact_attributes
  end

  def down
    drop_table :broadcast_messages
  end

  private

  def seed_contact_attributes
    CONTACT_ATTRIBUTES.each do |key, name, display_type, description|
      execute <<~SQL.squish
        INSERT INTO custom_attribute_definitions
          (attribute_key, attribute_display_name, attribute_display_type, attribute_description, attribute_model, account_id, created_at, updated_at)
        SELECT #{quote(key)}, #{quote(name)}, #{display_type}, #{quote(description)}, 1, accounts.id, NOW(), NOW()
        FROM accounts
        WHERE NOT EXISTS (
          SELECT 1 FROM custom_attribute_definitions d
          WHERE d.account_id = accounts.id AND d.attribute_key = #{quote(key)} AND d.attribute_model = 1
        )
      SQL
    end
  end
end
