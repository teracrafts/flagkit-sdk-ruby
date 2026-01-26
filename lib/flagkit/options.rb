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
    DEFAULT_KEY_ROTATION_GRACE_PERIOD = 300
    DEFAULT_MAX_PERSISTED_EVENTS = 10_000
    DEFAULT_PERSISTENCE_FLUSH_INTERVAL = 1000
    DEFAULT_EVALUATION_JITTER_ENABLED = false
    DEFAULT_EVALUATION_JITTER_MIN_MS = 5
    DEFAULT_EVALUATION_JITTER_MAX_MS = 15
    DEFAULT_BOOTSTRAP_VERIFICATION_ENABLED = true
    DEFAULT_BOOTSTRAP_VERIFICATION_MAX_AGE = 86_400_000 # 24 hours in milliseconds
    DEFAULT_BOOTSTRAP_VERIFICATION_ON_FAILURE = "warn"

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
                :local_port,
                :secondary_api_key,
                :key_rotation_grace_period,
                :strict_pii_mode,
                :enable_request_signing,
                :encrypt_cache,
                :persist_events,
                :event_storage_path,
                :max_persisted_events,
                :persistence_flush_interval,
                :evaluation_jitter_enabled,
                :evaluation_jitter_min_ms,
                :evaluation_jitter_max_ms,
                :bootstrap_verification_enabled,
                :bootstrap_verification_max_age,
                :bootstrap_verification_on_failure

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
    # @param secondary_api_key [String, nil] Secondary API key for key rotation
    # @param key_rotation_grace_period [Integer] Grace period in seconds during key rotation
    # @param strict_pii_mode [Boolean] Raise SecurityError instead of warning when PII detected
    # @param enable_request_signing [Boolean] Enable HMAC-SHA256 request signing for POST requests
    # @param encrypt_cache [Boolean] Enable AES-256-GCM encryption for cached data
    # @param persist_events [Boolean] Enable crash-resilient event persistence
    # @param event_storage_path [String, nil] Directory for event storage (defaults to OS temp dir)
    # @param max_persisted_events [Integer] Maximum events to persist
    # @param persistence_flush_interval [Integer] Milliseconds between disk writes
    # @param evaluation_jitter_enabled [Boolean] Enable timing jitter for cache timing attack protection
    # @param evaluation_jitter_min_ms [Integer] Minimum jitter delay in milliseconds
    # @param evaluation_jitter_max_ms [Integer] Maximum jitter delay in milliseconds
    # @param bootstrap_verification_enabled [Boolean] Enable HMAC-SHA256 signature verification for bootstrap data
    # @param bootstrap_verification_max_age [Integer] Maximum age in milliseconds for bootstrap data
    # @param bootstrap_verification_on_failure [String] Action on verification failure: 'warn', 'error', or 'ignore'
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
      local_port: nil,
      secondary_api_key: nil,
      key_rotation_grace_period: DEFAULT_KEY_ROTATION_GRACE_PERIOD,
      strict_pii_mode: false,
      enable_request_signing: true,
      encrypt_cache: false,
      persist_events: false,
      event_storage_path: nil,
      max_persisted_events: DEFAULT_MAX_PERSISTED_EVENTS,
      persistence_flush_interval: DEFAULT_PERSISTENCE_FLUSH_INTERVAL,
      evaluation_jitter_enabled: DEFAULT_EVALUATION_JITTER_ENABLED,
      evaluation_jitter_min_ms: DEFAULT_EVALUATION_JITTER_MIN_MS,
      evaluation_jitter_max_ms: DEFAULT_EVALUATION_JITTER_MAX_MS,
      bootstrap_verification_enabled: DEFAULT_BOOTSTRAP_VERIFICATION_ENABLED,
      bootstrap_verification_max_age: DEFAULT_BOOTSTRAP_VERIFICATION_MAX_AGE,
      bootstrap_verification_on_failure: DEFAULT_BOOTSTRAP_VERIFICATION_ON_FAILURE
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
      @secondary_api_key = secondary_api_key
      @key_rotation_grace_period = key_rotation_grace_period
      @strict_pii_mode = strict_pii_mode
      @enable_request_signing = enable_request_signing
      @encrypt_cache = encrypt_cache
      @persist_events = persist_events
      @event_storage_path = event_storage_path || default_event_storage_path
      @max_persisted_events = max_persisted_events
      @persistence_flush_interval = persistence_flush_interval
      @evaluation_jitter_enabled = evaluation_jitter_enabled
      @evaluation_jitter_min_ms = evaluation_jitter_min_ms
      @evaluation_jitter_max_ms = evaluation_jitter_max_ms
      @bootstrap_verification_enabled = bootstrap_verification_enabled
      @bootstrap_verification_max_age = bootstrap_verification_max_age
      @bootstrap_verification_on_failure = bootstrap_verification_on_failure
    end

    # Validates the options.
    #
    # @raise [Error] If validation fails
    # @raise [SecurityError] If local_port is used in production
    def validate!
      validate_api_key!
      validate_positive_integers!
      validate_local_port_restriction!
    end

    private

    def validate_local_port_restriction!
      return unless local_port

      env = ENV.fetch("RACK_ENV", ENV.fetch("RAILS_ENV", nil))
      return unless env == "production"

      raise SecurityError.new(
        ErrorCode::SECURITY_LOCAL_PORT_IN_PRODUCTION,
        "local_port cannot be used in production environment. " \
        "This is a security risk as it bypasses HTTPS and may expose traffic to interception."
      )
    end

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

    def default_event_storage_path
      require "tmpdir"
      File.join(Dir.tmpdir, "flagkit", "events")
    end
  end
end
