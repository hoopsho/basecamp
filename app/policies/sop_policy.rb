# frozen_string_literal: true

class SopPolicy < ApplicationPolicy
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

  def run?
    user&.admin?
  end

  def ai_builder?
    create?
  end

  def ai_builder_chat?
    create?
  end

  def ai_builder_create?
    create?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
