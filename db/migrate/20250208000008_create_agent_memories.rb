# frozen_string_literal: true

class CreateAgentMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_memories, id: :uuid do |t|
      t.references :agent, null: false, foreign_key: true, type: :uuid
      t.integer :memory_type, null: false
      t.text :content, null: false
      t.integer :importance, default: 5
      t.datetime :expires_at
      t.uuid :related_task_id

      t.timestamps
    end

    add_index :agent_memories, :memory_type
    add_index :agent_memories, :importance
    add_index :agent_memories, :expires_at
    add_index :agent_memories, :related_task_id
    add_index :agent_memories, [ :agent_id, :importance ]
    add_index :agent_memories, [ :agent_id, :created_at ]

    add_foreign_key :agent_memories, :tasks, column: :related_task_id
  end
end
