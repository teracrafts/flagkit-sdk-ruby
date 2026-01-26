# frozen_string_literal: true

require_relative "flagkit/version"

# Error module (must be loaded first as other modules depend on it)
require_relative "flagkit/error/error_code"
require_relative "flagkit/error/error_sanitizer"
require_relative "flagkit/error/flagkit_error"

# Utils module
require_relative "flagkit/utils/security"

# Types module
require_relative "flagkit/types/flag_type"
require_relative "flagkit/types/evaluation_reason"
require_relative "flagkit/types/flag_state"
require_relative "flagkit/types/evaluation_context"
require_relative "flagkit/types/evaluation_result"

# HTTP module
require_relative "flagkit/http/circuit_breaker"
require_relative "flagkit/http/http_client"

# Core module
require_relative "flagkit/core/cache"
require_relative "flagkit/core/encrypted_cache"
require_relative "flagkit/core/polling_manager"
require_relative "flagkit/core/event_persistence"
require_relative "flagkit/core/event_queue"

# Main components
require_relative "flagkit/options"
require_relative "flagkit/client"

# FlagKit Ruby SDK
#
# @example Basic usage
#   client = FlagKit.initialize("sdk_your_api_key")
#   enabled = FlagKit.get_boolean_value("my-feature", false)
#   FlagKit.shutdown
#
module FlagKit
  class << self
    # @return [Client, nil] The singleton client instance
    attr_reader :instance

    # Initializes the FlagKit SDK with the given API key.
    #
    # @param api_key [String] The API key for authentication
    # @param options [Hash] Additional configuration options
    # @return [Client] The initialized client
    # @raise [Error] If initialization fails or SDK is already initialized
    def initialize(api_key, **options)
      raise Error.new(ErrorCode::INIT_ALREADY_INITIALIZED, "FlagKit is already initialized") if @instance

      opts = Options.new(api_key: api_key, **options)
      opts.validate!

      @instance = Client.new(opts)
      @instance.initialize_sdk
      @instance
    end

    # Returns the singleton client instance.
    #
    # @return [Client, nil] The client instance, or nil if not initialized
    def client
      @instance
    end

    # Checks if the SDK has been initialized.
    #
    # @return [Boolean]
    def initialized?
      !@instance.nil?
    end

    # Shuts down the SDK and releases resources.
    def shutdown
      return unless @instance

      @instance.close
      @instance = nil
    end

    # Evaluates a boolean flag.
    #
    # @param key [String] The flag key
    # @param default_value [Boolean] Default value if flag not found
    # @param context [EvaluationContext, nil] Optional evaluation context
    # @return [Boolean]
    def get_boolean_value(key, default_value, context: nil)
      require_client.get_boolean_value(key, default_value, context: context)
    end

    # Evaluates a string flag.
    #
    # @param key [String] The flag key
    # @param default_value [String] Default value if flag not found
    # @param context [EvaluationContext, nil] Optional evaluation context
    # @return [String]
    def get_string_value(key, default_value, context: nil)
      require_client.get_string_value(key, default_value, context: context)
    end

    # Evaluates a number flag.
    #
    # @param key [String] The flag key
    # @param default_value [Numeric] Default value if flag not found
    # @param context [EvaluationContext, nil] Optional evaluation context
    # @return [Numeric]
    def get_number_value(key, default_value, context: nil)
      require_client.get_number_value(key, default_value, context: context)
    end

    # Evaluates a JSON flag.
    #
    # @param key [String] The flag key
    # @param default_value [Hash] Default value if flag not found
    # @param context [EvaluationContext, nil] Optional evaluation context
    # @return [Hash]
    def get_json_value(key, default_value, context: nil)
      require_client.get_json_value(key, default_value, context: context)
    end

    # Evaluates a flag and returns the full result.
    #
    # @param key [String] The flag key
    # @param default_value [Object] Default value if flag not found
    # @param context [EvaluationContext, nil] Optional evaluation context
    # @return [EvaluationResult]
    def evaluate(key, default_value = nil, context: nil)
      require_client.evaluate(key, default_value, context: context)
    end

    # Identifies a user.
    #
    # @param user_id [String] The user ID
    # @param attributes [Hash] Optional user attributes
    def identify(user_id, **attributes)
      require_client.identify(user_id, **attributes)
    end

    # Resets to anonymous user.
    def reset_context
      require_client.reset_context
    end

    # Tracks a custom event.
    #
    # @param event_type [String] The event type
    # @param data [Hash, nil] Optional event data
    def track(event_type, data = nil)
      require_client.track(event_type, data)
    end

    private

    def require_client
      raise "FlagKit is not initialized. Call FlagKit.initialize first." unless @instance

      @instance
    end
  end
end
