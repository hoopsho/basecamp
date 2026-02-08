# frozen_string_literal: true

class AgentMemoryPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
