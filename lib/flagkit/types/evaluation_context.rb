# frozen_string_literal: true

module FlagKit
  module Types
    # Context for flag evaluation containing user and custom attributes.
    class EvaluationContext
      PRIVATE_ATTRIBUTE_PREFIX = "_"

      attr_reader :user_id, :attributes

      # @param user_id [String, nil] The user identifier
      # @param attributes [Hash] Custom attributes
      def initialize(user_id: nil, **attributes)
        @user_id = user_id
        @attributes = attributes.transform_keys(&:to_s)
      end

      # Creates a new context with the given user ID.
      #
      # @param user_id [String] The user ID
      # @return [EvaluationContext]
      def with_user_id(user_id)
        self.class.new(user_id: user_id, **attributes)
      end

      # Creates a new context with the given attribute added.
      #
      # @param key [String, Symbol] The attribute key
      # @param value [Object] The attribute value
      # @return [EvaluationContext]
      def with_attribute(key, value)
        new_attrs = attributes.merge(key.to_s => value)
        self.class.new(user_id: user_id, **new_attrs)
      end

      # Creates a new context with multiple attributes added.
      #
      # @param attrs [Hash] The attributes to add
      # @return [EvaluationContext]
      def with_attributes(attrs)
        new_attrs = attributes.merge(attrs.transform_keys(&:to_s))
        self.class.new(user_id: user_id, **new_attrs)
      end

      # Merges another context into this one.
      # The other context takes precedence.
      #
      # @param other [EvaluationContext, nil] The other context
      # @return [EvaluationContext]
      def merge(other)
        return self unless other

        new_user_id = other.user_id || user_id
        new_attrs = attributes.merge(other.attributes)
        self.class.new(user_id: new_user_id, **new_attrs)
      end

      # Creates a copy with private attributes stripped.
      #
      # @return [EvaluationContext]
      def strip_private_attributes
        public_attrs = attributes.reject { |key, _| key.start_with?(PRIVATE_ATTRIBUTE_PREFIX) }
        self.class.new(user_id: user_id, **public_attrs)
      end

      # Checks if the context is empty.
      #
      # @return [Boolean]
      def empty?
        user_id.nil? && attributes.empty?
      end

      # Gets an attribute value.
      #
      # @param key [String, Symbol] The attribute key
      # @return [Object, nil]
      def [](key)
        attributes[key.to_s]
      end

      # Converts the context to a hash for API requests.
      #
      # @return [Hash]
      def to_h
        result = {}
        result["userId"] = user_id if user_id
        result["attributes"] = attributes unless attributes.empty?
        result
      end

      # Creates a context from a hash.
      #
      # @param data [Hash] The data hash
      # @return [EvaluationContext]
      def self.from_hash(data)
        return new if data.nil?

        user_id = data["userId"] || data["user_id"] || data[:user_id]
        attrs = data["attributes"] || data[:attributes] || {}
        new(user_id: user_id, **attrs)
      end

      def ==(other)
        return false unless other.is_a?(EvaluationContext)

        user_id == other.user_id && attributes == other.attributes
      end

      def eql?(other)
        self == other
      end

      def hash
        [user_id, attributes].hash
      end
    end
  end

  # Alias for backward compatibility
  EvaluationContext = Types::EvaluationContext
end
