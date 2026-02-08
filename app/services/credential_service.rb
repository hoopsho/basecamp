# frozen_string_literal: true

class CredentialService
  class CredentialError < StandardError; end
  class MissingCredentialError < CredentialError; end
  class ExpiredCredentialError < CredentialError; end
  class RefreshFailedError < CredentialError; end

  SUPPORTED_SERVICES = %w[anthropic slack ses crm].freeze

  def self.get(service_name, credential_type = :api_key)
    new.get(service_name, credential_type)
  end

  def self.get_value(service_name, credential_type = :api_key)
    cred = get(service_name, credential_type)
    cred&.value
  end

  def self.refresh_oauth_token(credential_id)
    new.refresh_oauth_token(credential_id)
  end

  def self.rotate_api_key(service_name)
    new.rotate_api_key(service_name)
  end

  def self.create_or_update(service_name, credential_type, value, options = {})
    new.create_or_update(service_name, credential_type, value, options)
  end

  def self.check_all_credentials
    new.check_all_credentials
  end

  def get(service_name, credential_type = :api_key)
    validate_service!(service_name)

    cred = Credential.usable
                     .for_service(service_name)
                     .by_type(credential_type)
                     .first

    if cred.nil?
      raise MissingCredentialError, "No active credential found for #{service_name}:#{credential_type}"
    end

    if cred.expired?
      raise ExpiredCredentialError, "Credential for #{service_name}:#{credential_type} has expired"
    end

    cred
  end

  def refresh_oauth_token(credential_id)
    cred = Credential.active.find_by(id: credential_id)

    unless cred
      raise MissingCredentialError, "Credential not found: #{credential_id}"
    end

    unless cred.refreshable?
      raise CredentialError, 'Credential is not refreshable'
    end

    # This would implement OAuth refresh logic
    # For now, just mark it as expired
    cred.mark_expired!

    {
      success: false,
      error: 'OAuth refresh not yet implemented'
    }
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  def rotate_api_key(service_name)
    validate_service!(service_name)

    # This would implement API key rotation
    # For now, just return instructions
    {
      success: true,
      message: "API key rotation for #{service_name} would be implemented here",
      instructions: [
        "1. Generate new API key in #{service_name} admin panel",
        '2. Update credential using CredentialService.create_or_update',
        '3. Revoke old API key'
      ]
    }
  end

  def create_or_update(service_name, credential_type, value, options = {})
    validate_service!(service_name)

    cred = Credential.for_service(service_name)
                     .by_type(credential_type)
                     .first

    if cred
      # Update existing
      cred.update!(
        value: value,
        scopes: options[:scopes] || cred.scopes,
        expires_at: options[:expires_at] || cred.expires_at,
        refresh_token: options[:refresh_token] || cred.refresh_token,
        status: :active
      )

      {
        success: true,
        credential: cred,
        action: :updated
      }
    else
      # Create new
      cred = Credential.create!(
        service_name: service_name,
        credential_type: credential_type,
        value: value,
        scopes: options[:scopes] || [],
        expires_at: options[:expires_at],
        refresh_token: options[:refresh_token],
        status: :active
      )

      {
        success: true,
        credential: cred,
        action: :created
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  def check_all_credentials
    results = {}

    SUPPORTED_SERVICES.each do |service|
      results[service] = check_service_credentials(service)
    end

    {
      success: true,
      services: results,
      all_ok: results.values.all? { |r| r[:ok] }
    }
  end

  def check_service_credentials(service_name)
    credentials = Credential.for_service(service_name)

    if credentials.empty?
      return {
        ok: false,
        status: :missing,
        message: "No credentials configured for #{service_name}"
      }
    end

    active_creds = credentials.active
    expired_creds = credentials.expired
    revoked_creds = credentials.revoked

    usable = active_creds.select(&:usable?)
    expiring_soon = active_creds.select { |c| c.expires_soon?(days: 7) }

    {
      ok: usable.any?,
      status: usable.any? ? :ok : :no_usable,
      total: credentials.count,
      usable: usable.count,
      expired: expired_creds.count,
      revoked: revoked_creds.count,
      expiring_soon: expiring_soon.count,
      message: build_status_message(usable, expiring_soon, expired_creds)
    }
  end

  def revoke_credential(credential_id, reason = nil)
    cred = Credential.find_by(id: credential_id)

    unless cred
      raise MissingCredentialError, "Credential not found: #{credential_id}"
    end

    cred.mark_revoked!

    # Log the revocation
    Rails.logger.info "Credential revoked: #{credential_id} (#{cred.service_name}) - Reason: #{reason}"

    {
      success: true,
      credential: cred
    }
  end

  private

  def validate_service!(service_name)
    unless SUPPORTED_SERVICES.include?(service_name.to_s)
      raise CredentialError, "Unsupported service: #{service_name}. Supported: #{SUPPORTED_SERVICES.join(', ')}"
    end
  end

  def build_status_message(usable, expiring_soon, expired)
    messages = []

    if usable.empty?
      messages << 'No usable credentials'
    else
      messages << "#{usable.count} usable credential(s)"
    end

    if expiring_soon.any?
      messages << "#{expiring_soon.count} expiring within 7 days"
    end

    if expired.any?
      messages << "#{expired.count} expired"
    end

    messages.join(', ')
  end
end
