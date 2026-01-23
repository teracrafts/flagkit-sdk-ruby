# frozen_string_literal: true

module FlagKit
  module Types
    # Types of feature flags.
    module FlagType
      BOOLEAN = "boolean"
      STRING = "string"
      NUMBER = "number"
      JSON = "json"

      ALL = [BOOLEAN, STRING, NUMBER, JSON].freeze

      # Infers the flag type from a value.
      #
      # @param value [Object] The value to infer type from
      # @return [String] The inferred flag type
      def self.infer(value)
        case value
        when TrueClass, FalseClass
          BOOLEAN
        when String
          STRING
        when Numeric
          NUMBER
        else
          JSON
        end
      end

      # Parses a flag type string.
      #
      # @param value [String] The type string
      # @return [String] The normalized flag type
      def self.parse(value)
        return JSON unless value

        normalized = value.to_s.downcase
        ALL.include?(normalized) ? normalized : JSON
      end
    end
  end

  # Alias for backward compatibility
  FlagType = Types::FlagType
end
