# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def show?
    user&.admin? || user == record
  end

  def create?
    user&.admin?
  end

  def edit?
    user&.admin? || user == record
  end

  def update?
    user&.admin? || user == record
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
