# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      # No CSRF, no session, no cookies - this is a pure API controller.
      # No Pundit - webhooks are verified via signatures, not user auth.
    end
  end
end
