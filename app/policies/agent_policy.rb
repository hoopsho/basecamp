# frozen_string_literal: true

class AgentPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def update?
    user&.admin?
  end

  def pause?
    user&.admin?
  end

  def resume?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
