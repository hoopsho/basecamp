# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.integer :role, default: 0, null: false
      t.integer :theme_preference, default: 2, null: false

      t.timestamps
    end

    add_index :users, :email_address, unique: true
    add_index :users, :role
  end
end
