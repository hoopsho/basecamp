# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks, id: :uuid do |t|
      t.references :sop, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: true, type: :uuid
      t.integer :status, default: 0, null: false
      t.integer :current_step_position, default: 1
      t.jsonb :context, default: {}
      t.integer :priority, default: 5
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.uuid :parent_task_id
      t.string :slack_thread_ts

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :priority
    add_index :tasks, :parent_task_id
    add_index :tasks, :context, using: :gin
    add_index :tasks, [ :agent_id, :status ]
    add_index :tasks, [ :sop_id, :status ]

    add_foreign_key :tasks, :tasks, column: :parent_task_id
  end
end
