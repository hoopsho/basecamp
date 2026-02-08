# frozen_string_literal: true

class CreateSops < ActiveRecord::Migration[8.1]
  def change
    create_table :sops, id: :uuid do |t|
      t.references :agent, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :trigger_type, default: 0, null: false
      t.jsonb :trigger_config, default: {}
      t.string :required_services, array: true, default: []
      t.integer :status, default: 0, null: false
      t.integer :version, default: 1, null: false
      t.integer :max_tier, default: 3, null: false

      t.timestamps
    end

    add_index :sops, :slug, unique: true
    add_index :sops, :status
    add_index :sops, :trigger_type
    add_index :sops, :required_services, using: :gin
  end
end
