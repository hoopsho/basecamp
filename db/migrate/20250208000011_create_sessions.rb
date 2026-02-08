# frozen_string_literal: true

class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions, id: :string do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end

    add_index :sessions, :id, unique: true
  end
end
