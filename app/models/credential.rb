# frozen_string_literal: true

class Credential < ApplicationRecord
  encrypts :value
  encrypts :refresh_token

  validates :service_name, presence: true
  validates :credential_type, presence: true
  validates :value, presence: true
  validates :scopes, presence: true, allow_blank: true
  validates :service_name, uniqueness: { scope: :credential_type }, if: -> { active? }

  enum :credential_type, [
    :api_key,
    :oauth_token,
    :webhook_secret
  ], default: :api_key

  enum :status, [
    :active,
    :expired,
    :revoked
  ], default: :active

  scope :active, -> { where(status: :active) }
  scope :expired, -> { where(status: :expired) }
  scope :revoked, -> { where(status: :revoked) }
  scope :for_service, ->(service) { where(service_name: service) }
  scope :by_type, ->(type) { where(credential_type: type) }
  scope :usable, -> { active.where('expires_at IS NULL OR expires_at > ?', Time.current) }

  def active?
    status == 'active'
  end

  def expired?
    return status == 'expired' if status == 'expired'
    return false if expires_at.nil?

    expires_at <= Time.current
  end

  def revoked?
    status == 'revoked'
  end

  def usable?
    active? && !expired?
  end

  def mark_expired!
    update!(status: :expired) unless expired?
  end

  def mark_revoked!
    update!(status: :revoked) unless revoked?
  end

  def refreshable?
    refresh_token.present? && credential_type == 'oauth_token'
  end

  def has_scope?(scope)
    scopes.include?(scope.to_s)
  end

  def days_until_expiration
    return nil if expires_at.nil?
    return 0 if expired?

    (expires_at.to_date - Date.current).to_i
  end

  def expires_soon?(days: 7)
    return false if expires_at.nil?

    days_until_expiration <= days
  end

  def self.for_service_and_type(service_name, credential_type)
    active.for_service(service_name).by_type(credential_type).first
  end

  def self.find_usable(service_name, credential_type)
    usable.for_service(service_name).by_type(credential_type).first
  end

  def human_readable_credential_type
    case credential_type
    when 'api_key'
      'API Key'
    when 'oauth_token'
      'OAuth Token'
    when 'webhook_secret'
      'Webhook Secret'
    end
  end

  def human_readable_status
    case status
    when 'active'
      'Active'
    when 'expired'
      'Expired'
    when 'revoked'
      'Revoked'
    end
  end
end
