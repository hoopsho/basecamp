# frozen_string_literal: true

class CreateWatchers < ActiveRecord::Migration[8.1]
  def change
    create_table :watchers, id: :uuid do |t|
      t.references :agent, null: false, foreign_key: true, type: :uuid
      t.references :sop, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.integer :check_type, null: false
      t.jsonb :check_config, default: {}
      t.integer :interval_minutes, null: false
      t.datetime :last_checked_at
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :watchers, :status
    add_index :watchers, :check_type
    add_index :watchers, :last_checked_at
  end
end
