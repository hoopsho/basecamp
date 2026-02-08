# frozen_string_literal: true

class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :status, default: 0, null: false
      t.string :slack_channel
      t.integer :loop_interval_minutes
      t.jsonb :capabilities, default: {}

      t.timestamps
    end

    add_index :agents, :slug, unique: true
    add_index :agents, :status
    add_index :agents, :capabilities, using: :gin
  end
end
