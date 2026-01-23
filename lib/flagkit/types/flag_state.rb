# frozen_string_literal: true

module FlagKit
  module Types
    # Represents the state of a feature flag.
    class FlagState
      attr_reader :key, :value, :enabled, :version, :flag_type, :last_modified, :metadata

      # @param key [String] The flag key
      # @param value [Object] The flag value
      # @param enabled [Boolean] Whether the flag is enabled
      # @param version [Integer] The flag version
      # @param flag_type [String] The flag type
      # @param last_modified [String, nil] ISO 8601 timestamp
      # @param metadata [Hash, nil] Additional metadata
      def initialize(key:, value:, enabled: true, version: 0, flag_type: nil, last_modified: nil, metadata: nil)
        @key = key
        @value = value
        @enabled = enabled
        @version = version
        @flag_type = flag_type || FlagType.infer(value)
        @last_modified = last_modified || Time.now.utc.iso8601
        @metadata = metadata || {}
      end

      # @return [Boolean] The value as a boolean
      def boolean_value
        value == true
      end

      # @return [String, nil] The value as a string
      def string_value
        value&.to_s
      end

      # @return [Float] The value as a float
      def number_value
        value.is_a?(Numeric) ? value.to_f : 0.0
      end

      # @return [Integer] The value as an integer
      def int_value
        value.is_a?(Numeric) ? value.to_i : 0
      end

      # @return [Hash, nil] The value as a hash
      def json_value
        value.is_a?(Hash) ? value : nil
      end

      # Creates a FlagState from a hash.
      #
      # @param data [Hash] The data hash
      # @return [FlagState]
      def self.from_hash(data)
        new(
          key: data["key"] || data[:key],
          value: data["value"] || data[:value],
          enabled: data.fetch("enabled", data.fetch(:enabled, true)),
          version: data["version"] || data[:version] || 0,
          flag_type: data["flagType"] || data[:flag_type],
          last_modified: data["lastModified"] || data[:last_modified],
          metadata: data["metadata"] || data[:metadata]
        )
      end

      # Converts the flag state to a hash.
      #
      # @return [Hash]
      def to_h
        {
          key: key,
          value: value,
          enabled: enabled,
          version: version,
          flag_type: flag_type,
          last_modified: last_modified,
          metadata: metadata
        }
      end

      def ==(other)
        return false unless other.is_a?(FlagState)

        key == other.key && value == other.value && enabled == other.enabled && version == other.version
      end

      def eql?(other)
        self == other
      end

      def hash
        [key, value, enabled, version].hash
      end
    end
  end

  # Alias for backward compatibility
  FlagState = Types::FlagState
end
