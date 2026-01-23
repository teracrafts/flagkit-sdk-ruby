# frozen_string_literal: true

module FlagKit
  # Configuration options for the FlagKit SDK.
  class Options
    DEFAULT_POLLING_INTERVAL = 30
    DEFAULT_CACHE_TTL = 300
    DEFAULT_MAX_CACHE_SIZE = 1000
    DEFAULT_EVENT_BATCH_SIZE = 10
    DEFAULT_EVENT_FLUSH_INTERVAL = 30
    DEFAULT_TIMEOUT = 10
    DEFAULT_RETRY_ATTEMPTS = 3
    DEFAULT_CIRCUIT_BREAKER_THRESHOLD = 5
    DEFAULT_CIRCUIT_BREAKER_RESET_TIMEOUT = 30

    attr_reader :api_key,
                :polling_interval,
                :cache_ttl,
                :max_cache_size,
                :cache_enabled,
                :event_batch_size,
                :event_flush_interval,
                :events_enabled,
                :timeout,
                :retry_attempts,
                :circuit_breaker_threshold,
                :circuit_breaker_reset_timeout,
                :bootstrap,
                :logger,
                :storage,
                :local_port

    # @param api_key [String] The API key
    # @param polling_interval [Integer] Polling interval in seconds
    # @param cache_ttl [Integer] Cache TTL in seconds
    # @param max_cache_size [Integer] Maximum cache size
    # @param cache_enabled [Boolean] Whether caching is enabled
    # @param event_batch_size [Integer] Event batch size
    # @param event_flush_interval [Integer] Event flush interval in seconds
    # @param events_enabled [Boolean] Whether events are enabled
    # @param timeout [Integer] Request timeout in seconds
    # @param retry_attempts [Integer] Number of retry attempts
    # @param circuit_breaker_threshold [Integer] Circuit breaker failure threshold
    # @param circuit_breaker_reset_timeout [Integer] Circuit breaker reset timeout in seconds
    # @param bootstrap [Hash, nil] Bootstrap data
    # @param logger [Object, nil] Logger instance
    # @param storage [Object, nil] Storage adapter
    # @param local_port [Integer, nil] Local development server port (uses http://localhost:{port}/api/v1)
    def initialize(
      api_key:,
      polling_interval: DEFAULT_POLLING_INTERVAL,
      cache_ttl: DEFAULT_CACHE_TTL,
      max_cache_size: DEFAULT_MAX_CACHE_SIZE,
      cache_enabled: true,
      event_batch_size: DEFAULT_EVENT_BATCH_SIZE,
      event_flush_interval: DEFAULT_EVENT_FLUSH_INTERVAL,
      events_enabled: true,
      timeout: DEFAULT_TIMEOUT,
      retry_attempts: DEFAULT_RETRY_ATTEMPTS,
      circuit_breaker_threshold: DEFAULT_CIRCUIT_BREAKER_THRESHOLD,
      circuit_breaker_reset_timeout: DEFAULT_CIRCUIT_BREAKER_RESET_TIMEOUT,
      bootstrap: nil,
      logger: nil,
      storage: nil,
      local_port: nil
    )
      @api_key = api_key
      @polling_interval = polling_interval
      @cache_ttl = cache_ttl
      @max_cache_size = max_cache_size
      @cache_enabled = cache_enabled
      @event_batch_size = event_batch_size
      @event_flush_interval = event_flush_interval
      @events_enabled = events_enabled
      @timeout = timeout
      @retry_attempts = retry_attempts
      @circuit_breaker_threshold = circuit_breaker_threshold
      @circuit_breaker_reset_timeout = circuit_breaker_reset_timeout
      @bootstrap = bootstrap
      @logger = logger
      @storage = storage
      @local_port = local_port
    end

    # Validates the options.
    #
    # @raise [Error] If validation fails
    def validate!
      validate_api_key!
      validate_positive_integers!
    end

    private

    def validate_api_key!
      raise Error.config_error(ErrorCode::CONFIG_INVALID_API_KEY, "API key is required") if api_key.nil? || api_key.empty?

      unless api_key.start_with?("sdk_", "srv_", "cli_")
        raise Error.config_error(ErrorCode::CONFIG_INVALID_API_KEY, "Invalid API key format")
      end
    end

    def validate_positive_integers!
      if polling_interval <= 0
        raise Error.config_error(ErrorCode::CONFIG_INVALID_POLLING_INTERVAL, "Polling interval must be positive")
      end

      raise Error.config_error(ErrorCode::CONFIG_INVALID_CACHE_TTL, "Cache TTL must be positive") if cache_ttl <= 0
    end
  end
end
