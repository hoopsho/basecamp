# frozen_string_literal: true

module SeoHelper
  def page_title(title = nil)
    content_for(:page_title, title) if title
    content_for?(:page_title) ? "#{content_for(:page_title)} | #{app_name}" : app_name
  end

  def page_description(description = nil)
    content_for(:page_description, description) if description
    content_for(:page_description) if content_for?(:page_description)
  end

  def app_name
    Rails.application.class.module_parent_name.underscore.titleize
  end
end
