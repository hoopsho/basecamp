# frozen_string_literal: true

module Admin
  class CredentialsController < BaseController
    before_action :set_credential, only: [ :show, :refresh ]
    before_action :require_admin, only: [ :refresh ]

    def index
      @credentials = policy_scope(Credential).order(:service_name, :credential_type)
    end

    def show
      authorize @credential
    end

    def refresh
      authorize @credential

      result = CredentialService.refresh_oauth_token(@credential.id)

      if result[:success]
        redirect_to admin_credential_path(@credential), notice: 'Credential has been refreshed.'
      else
        redirect_to admin_credential_path(@credential), alert: "Refresh failed: #{result[:error]}"
      end
    end

    private

    def set_credential
      @credential = Credential.find(params[:id])
    end
  end
end
