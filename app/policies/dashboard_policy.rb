# frozen_string_literal: true

class DashboardPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
