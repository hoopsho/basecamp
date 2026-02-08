# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user

  before_create do
    self.id = SecureRandom.base36(20)
  end
end
