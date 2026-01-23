# frozen_string_literal: true

module FlagKit
  # Result of evaluating a feature flag.
  class EvaluationResult
    attr_reader :flag_key, :value, :enabled, :reason, :version, :timestamp

    # @param flag_key [String] The flag key
    # @param value [Object] The evaluated value
    # @param enabled [Boolean] Whether the flag is enabled
    # @param reason [String] The evaluation reason
    # @param version [Integer] The flag version
    # @param timestamp [Time] When the evaluation occurred
    def initialize(flag_key:, value:, enabled: false, reason: EvaluationReason::DEFAULT, version: 0, timestamp: nil)
      @flag_key = flag_key
      @value = value
      @enabled = enabled
      @reason = reason
      @version = version
      @timestamp = timestamp || Time.now
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

    # Creates a default result.
    #
    # @param key [String] The flag key
    # @param default_value [Object] The default value
    # @param reason [String] The reason
    # @return [EvaluationResult]
    def self.default_result(key, default_value, reason)
      new(flag_key: key, value: default_value, enabled: false, reason: reason)
    end

    # Converts the result to a hash.
    #
    # @return [Hash]
    def to_h
      {
        flag_key: flag_key,
        value: value,
        enabled: enabled,
        reason: reason,
        version: version,
        timestamp: timestamp.iso8601
      }
    end
  end
end
