# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :require_admin, only: [ :index, :new, :create ]
    before_action :set_user, only: [ :edit, :update ]

    def index
      @users = policy_scope(User).order(:email_address)
    end

    def new
      @user = User.new
      authorize @user
    end

    def create
      @user = User.new(user_params)
      authorize @user

      if @user.save
        redirect_to admin_users_path, notice: 'User was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @user
    end

    def update
      authorize @user

      if @user.update(user_params)
        redirect_to admin_root_path, notice: 'Profile was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      if Current.user&.admin?
        params.require(:user).permit(:email_address, :password, :role, :theme_preference)
      else
        params.require(:user).permit(:email_address, :password, :theme_preference)
      end
    end
  end
end
