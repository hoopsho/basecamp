class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
