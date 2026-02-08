# frozen_string_literal: true

class TaskPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def retry?
    user&.admin?
  end

  def cancel?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
