# frozen_string_literal: true

# Shared concern for models with JSONB config/context fields
# Provides safe accessors and helpers for working with JSONB data
module HasJsonbAccessors
  extend ActiveSupport::Concern

  class_methods do
    def jsonb_accessor(field_name, *keys)
      keys.each do |key|
        define_method(key) do
          send(field_name)&.dig(key.to_s)
        end

        define_method("#{key}=") do |value|
          self[field_name] ||= {}
          self[field_name][key.to_s] = value
        end

        define_method("#{key}?") do
          send(field_name)&.key?(key.to_s)
        end
      end
    end

    def jsonb_array_accessor(field_name, key)
      define_method(key) do
        send(field_name)&.dig(key.to_s) || []
      end

      define_method("#{key}=") do |value|
        self[field_name] ||= {}
        self[field_name][key.to_s] = Array(value)
      end

      define_method("#{key}?") do
        (send(field_name)&.dig(key.to_s) || []).any?
      end

      define_method("add_to_#{key}") do |value|
        self[field_name] ||= {}
        self[field_name][key.to_s] ||= []
        self[field_name][key.to_s] << value unless self[field_name][key.to_s].include?(value)
        save!
      end

      define_method("remove_from_#{key}") do |value|
        self[field_name] ||= {}
        self[field_name][key.to_s] ||= []
        self[field_name][key.to_s].delete(value)
        save!
      end
    end
  end
end
