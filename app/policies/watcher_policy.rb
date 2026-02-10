# frozen_string_literal: true

class WatcherPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def create?
    user&.admin?
  end

  def update?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def pause?
    user&.admin?
  end

  def resume?
    user&.admin?
  end

  def run_now?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
