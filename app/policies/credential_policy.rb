# frozen_string_literal: true

class CredentialPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def refresh?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
