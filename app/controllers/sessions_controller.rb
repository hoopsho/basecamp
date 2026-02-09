# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [ :new, :create ]
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  allow_unauthenticated_access only: [ :new, :create ]

  def new
    redirect_to admin_root_path if authenticated?
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for(user)
      redirect_to admin_root_path, notice: 'Welcome back!'
    else
      flash.now[:alert] = 'Invalid email or password'
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: 'You have been logged out'
  end
end
