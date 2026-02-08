# frozen_string_literal: true

class CreateSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :steps, id: :uuid do |t|
      t.references :sop, null: false, foreign_key: true, type: :uuid
      t.integer :position, null: false
      t.string :name, null: false
      t.text :description
      t.integer :step_type, default: 0, null: false
      t.jsonb :config, default: {}
      t.integer :llm_tier, default: 0
      t.integer :max_llm_tier, default: 3
      t.string :on_success, default: 'next'
      t.string :on_failure, default: 'fail'
      t.string :on_uncertain, default: 'escalate_tier'
      t.integer :max_retries, default: 3
      t.integer :timeout_seconds, default: 300

      t.timestamps
    end

    add_index :steps, [ :sop_id, :position ], unique: true
    add_index :steps, :step_type
  end
end
