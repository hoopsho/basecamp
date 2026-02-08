# frozen_string_literal: true

class CreateTaskEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :task_events, id: :uuid do |t|
      t.references :task, null: false, foreign_key: true, type: :uuid
      t.references :step, foreign_key: true, type: :uuid
      t.integer :event_type, null: false
      t.integer :llm_tier_used
      t.string :llm_model
      t.integer :llm_tokens_in
      t.integer :llm_tokens_out
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.float :confidence_score
      t.integer :duration_ms

      t.datetime :created_at, null: false
    end

    add_index :task_events, :event_type
    add_index :task_events, :created_at
    add_index :task_events, [ :task_id, :created_at ]
  end
end
