# frozen_string_literal: true

class CreateCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials, id: :uuid do |t|
      t.string :service_name, null: false
      t.integer :credential_type, null: false
      t.text :encrypted_value, null: false
      t.string :scopes, array: true, default: []
      t.datetime :expires_at
      t.text :encrypted_refresh_token
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :credentials, :service_name
    add_index :credentials, :credential_type
    add_index :credentials, :status
    add_index :credentials, :expires_at
    add_index :credentials, :scopes, using: :gin
    add_index :credentials, [ :service_name, :status ]
  end
end
