# frozen_string_literal: true

class RenameEncryptedColumnsInCredentials < ActiveRecord::Migration[8.1]
  def change
    # Rails AR Encryption uses `encrypts :value` which expects a `value` column.
    # The original migration used `encrypted_value` (attr_encrypted convention),
    # but Rails native encryption stores ciphertext in the same-named column.
    rename_column :credentials, :encrypted_value, :value
    rename_column :credentials, :encrypted_refresh_token, :refresh_token

    # Remove NOT NULL on value since encryption changes column contents
    change_column_null :credentials, :value, true
  end
end
