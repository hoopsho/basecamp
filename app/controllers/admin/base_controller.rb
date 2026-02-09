# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    layout 'admin'

    before_action :require_authentication
    before_action :set_current_user
    after_action :verify_authorized, unless: -> { action_name == 'index' }
    after_action :verify_policy_scoped, if: -> { action_name == 'index' }

    private

    def set_current_user
      Current.user = Current.session&.user
    end

    def require_authentication
      unless authenticated?
        redirect_to new_session_path, alert: 'Please sign in to continue'
      end
    end

    def require_admin
      unless Current.user&.admin?
        redirect_to admin_root_path, alert: 'You do not have permission to access this page'
      end
    end
  end
end
