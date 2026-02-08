# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  validates :email_address, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  normalizes :email_address, with: ->(email) { email.to_s.downcase.strip }

  enum :role, [
    :admin,
    :viewer
  ], default: :viewer

  enum :theme_preference, [
    :dark,
    :light,
    :system
  ], default: :system

  scope :admins, -> { where(role: :admin) }
  scope :viewers, -> { where(role: :viewer) }
  scope :active, -> { where('created_at > ?', 90.days.ago) }

  def admin?
    role == 'admin'
  end

  def viewer?
    role == 'viewer'
  end

  def can_manage?
    admin?
  end

  def can_view_only?
    viewer?
  end

  def theme
    theme_preference
  end

  def prefers_dark_mode?
    theme_preference == 'dark'
  end

  def prefers_light_mode?
    theme_preference == 'light'
  end

  def follows_system_theme?
    theme_preference == 'system'
  end

  def display_name
    email_address.split('@').first.titleize
  end

  def self.authenticate_by_email_and_password(email, password)
    user = find_by(email_address: email.to_s.downcase.strip)
    return nil unless user
    return nil unless user.authenticate(password)

    user
  end

  def self.find_by_email(email)
    find_by(email_address: email.to_s.downcase.strip)
  end
end
