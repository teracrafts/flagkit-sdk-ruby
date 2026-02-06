# frozen_string_literal: true

module FlagKit
  # The main FlagKit client for evaluating feature flags.
  class Client
    attr_reader :options, :ready

    # @param options [Options] The client options
    def initialize(options)
      @options = options
      @ready = false
      @ready_mutex = Mutex.new
      @ready_condition = ConditionVariable.new
      @context = EvaluationContext.new
      @context_mutex = Mutex.new

      setup_components
    end

    # Initializes the SDK by fetching initial flag state.
    def initialize_sdk
      load_bootstrap if options.bootstrap
      fetch_initial_flags
      start_background_tasks
      mark_ready
    rescue StandardError => e
      log(:error, "Failed to initialize SDK: #{e.message}")
      mark_ready
      raise Error.init_error("Failed to initialize: #{e.message}")
    end

    # Waits for the SDK to be ready.
    #
    # @param timeout [Integer, nil] Maximum time to wait in seconds
    # @return [Boolean] Whether the SDK is ready
    def wait_for_ready(timeout: nil)
      @ready_mutex.synchronize do
        return true if @ready

        timeout ? @ready_condition.wait(@ready_mutex, timeout) : wait_until_ready
        @ready
      end
    end

    # Checks if the SDK is ready.
    #
    # @return [Boolean]
    def ready?
      @ready_mutex.synchronize { @ready }
    end

    # Sets the user context.
    #
    # @param user_id [String] The user ID
    # @param attributes [Hash] User attributes
    def identify(user_id, **attributes)
      @context_mutex.synchronize do
        @context = EvaluationContext.new(user_id: user_id, **attributes)
      end
    end

    # Clears the user context.
    def reset_context
      @context_mutex.synchronize { @context = EvaluationContext.new }
    end

    # Gets the current context.
    #
    # @return [EvaluationContext]
    def context
      @context_mutex.synchronize { @context.dup }
    end

    # Evaluates a flag and returns the full result.
    #
    # @param key [String] The flag key
    # @param default_value [Object] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [EvaluationResult]
    def evaluate(key, default_value, context: nil)
      apply_evaluation_jitter
      cached_result = try_cached_evaluation(key)
      return cached_result if cached_result

      fetch_and_cache_flag(key, merge_context(context), default_value)
    end

    # Gets a boolean flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Boolean] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Boolean]
    def get_boolean_value(key, default_value, context: nil)
      evaluate(key, default_value, context: context).boolean_value
    end

    # Gets a string flag value.
    #
    # @param key [String] The flag key
    # @param default_value [String] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [String, nil]
    def get_string_value(key, default_value, context: nil)
      evaluate(key, default_value, context: context).string_value || default_value
    end

    # Gets a number flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Float] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Float]
    def get_number_value(key, default_value, context: nil)
      evaluate(key, default_value, context: context).number_value
    end

    # Gets an integer flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Integer] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Integer]
    def get_int_value(key, default_value, context: nil)
      evaluate(key, default_value, context: context).int_value
    end

    # Gets a JSON flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Hash] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Hash, nil]
    def get_json_value(key, default_value, context: nil)
      evaluate(key, default_value, context: context).json_value || default_value
    end

    # Checks if a flag exists in the cache.
    #
    # @param key [String] The flag key
    # @return [Boolean]
    def has_flag?(key)
      return false unless options.cache_enabled

      @cache.has?(key)
    end

    # Returns all cached flag keys.
    #
    # @return [Array<String>]
    def get_all_flag_keys
      return [] unless options.cache_enabled

      @cache.keys
    end

    # Evaluates all cached flags and returns results.
    #
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Hash<String, EvaluationResult>]
    def evaluate_all(context: nil)
      return {} unless options.cache_enabled

      results = {}
      @cache.keys.each do |key|
        cached = @cache.get(key)
        results[key] = build_result(key, cached, EvaluationReason::CACHED) if cached
      end
      results
    end

    # Tracks an analytics event.
    #
    # @param event_type [String] The event type
    # @param data [Hash, nil] Optional event data
    def track(event_type, data = nil)
      return unless options.events_enabled && @event_queue

      @event_queue.enqueue(build_event(event_type, data))
    end

    # Closes the client and releases resources.
    def close
      @polling_manager.stop
      @event_queue&.stop
      @cache.clear
      log(:info, 'Client closed')
    end

    private

    def setup_components
      @circuit_breaker = build_circuit_breaker
      @http_client = build_http_client
      @cache = build_cache
      @polling_manager = build_polling_manager
      @event_queue = build_event_queue if options.events_enabled
    end

    def build_circuit_breaker
      CircuitBreaker.new(
        failure_threshold: options.circuit_breaker_threshold,
        reset_timeout: options.circuit_breaker_reset_timeout
      )
    end

    def build_http_client
      HttpClient.new(
        api_key: options.api_key, timeout: options.timeout,
        retry_attempts: options.retry_attempts, circuit_breaker: @circuit_breaker,
        logger: options.logger, secondary_api_key: options.secondary_api_key,
        key_rotation_grace_period: options.key_rotation_grace_period,
        enable_request_signing: options.enable_request_signing
      )
    end

    def build_cache
      return build_encrypted_cache if options.encrypt_cache

      Cache.new(ttl: options.cache_ttl, max_size: options.max_cache_size)
    end

    def build_encrypted_cache
      EncryptedCache.new(
        api_key: options.api_key, ttl: options.cache_ttl,
        max_size: options.max_cache_size, logger: options.logger
      )
    end

    def build_polling_manager
      PollingManager.new(
        interval: options.polling_interval,
        on_update: method(:poll_for_updates),
        logger: options.logger
      )
    end

    def build_event_queue
      EventQueue.new(
        batch_size: options.event_batch_size,
        flush_interval: options.event_flush_interval,
        on_flush: method(:send_events),
        logger: options.logger
      )
    end

    def mark_ready
      @ready_mutex.synchronize do
        @ready = true
        @ready_condition.broadcast
      end
    end

    def wait_until_ready
      @ready_condition.wait(@ready_mutex) until @ready
    end

    def try_cached_evaluation(key)
      return nil unless options.cache_enabled

      cached = @cache.get(key)
      cached ? build_result(key, cached, EvaluationReason::CACHED) : nil
    end

    def fetch_and_cache_flag(key, effective_context, default_value)
      response = @http_client.post('/sdk/evaluate', {
                                     key: key, context: effective_context.strip_private_attributes.to_h
                                   })
      flag_state = FlagState.from_hash(response)
      cache_flag(key, flag_state) if options.cache_enabled
      build_result(key, flag_state, EvaluationReason::SERVER)
    rescue Error => e
      log(:warn, "Evaluation failed for #{key}: #{e.message}")
      EvaluationResult.default_result(key, default_value, EvaluationReason::ERROR)
    end

    def build_event(event_type, data)
      {
        type: event_type, timestamp: Time.now.utc.iso8601,
        userId: context.user_id, data: data
      }.compact
    end

    def load_bootstrap
      return unless options.bootstrap.is_a?(Hash)

      flags = extract_bootstrap_flags(options.bootstrap)
      flags&.each { |flag_data| cache_flag(FlagState.from_hash(flag_data).key, FlagState.from_hash(flag_data)) }
    end

    def extract_bootstrap_flags(bootstrap)
      return legacy_bootstrap_flags(bootstrap) unless bootstrap_has_flags_key?(bootstrap)

      flags = bootstrap['flags'] || bootstrap[:flags] || []
      return flags unless should_verify_bootstrap?(bootstrap)

      verify_and_return_flags(bootstrap, flags)
    end

    def bootstrap_has_flags_key?(bootstrap)
      bootstrap.key?('flags') || bootstrap.key?(:flags)
    end

    def should_verify_bootstrap?(bootstrap)
      (bootstrap.key?('signature') || bootstrap.key?(:signature)) && options.bootstrap_verification_enabled
    end

    def legacy_bootstrap_flags(bootstrap)
      bootstrap.is_a?(Array) ? bootstrap : []
    end

    def verify_and_return_flags(bootstrap, flags)
      result = Utils::Security.verify_bootstrap_signature(
        bootstrap, options.api_key, max_age_ms: options.bootstrap_verification_max_age
      )
      return flags if result[:valid]

      handle_bootstrap_verification_failure(result[:error])
      options.bootstrap_verification_on_failure == 'error' ? nil : flags
    end

    def handle_bootstrap_verification_failure(error_message)
      return raise_bootstrap_error(error_message) if options.bootstrap_verification_on_failure == 'error'

      log_bootstrap_warning(error_message) unless options.bootstrap_verification_on_failure == 'ignore'
    end

    def raise_bootstrap_error(error_message)
      raise Error.config_error(ErrorCode::CONFIG_INVALID_BOOTSTRAP, "Bootstrap verification failed: #{error_message}")
    end

    def log_bootstrap_warning(error_message)
      log(:warn, "Bootstrap verification failed: #{error_message}. Using bootstrap data anyway.")
    end

    def fetch_initial_flags
      response = @http_client.get('/sdk/init')
      process_flags_response(response)
      check_version_metadata(response)
    rescue Error => e
      log(:warn, "Failed to fetch initial flags: #{e.message}")
    end

    # Check SDK version metadata from init response and emit appropriate warnings.
    #
    # Per spec, the SDK should parse and surface:
    # - sdkVersionMin: Minimum required version (older may not work)
    # - sdkVersionRecommended: Recommended version for optimal experience
    # - sdkVersionLatest: Latest available version
    # - deprecationWarning: Server-provided deprecation message
    #
    # @param response [Hash] The init response
    def check_version_metadata(response)
      metadata = response['metadata'] || response[:metadata]
      return unless metadata

      current_version = VERSION

      # Check for server-provided deprecation warning first
      deprecation_warning = metadata['deprecationWarning'] || metadata[:deprecationWarning]
      if deprecation_warning && !deprecation_warning.empty?
        log(:warn, "Deprecation Warning: #{deprecation_warning}")
      end

      # Check minimum version requirement
      sdk_version_min = metadata['sdkVersionMin'] || metadata[:sdkVersionMin]
      if sdk_version_min && Utils::Version.less_than?(current_version, sdk_version_min)
        log(:error, "SDK version #{current_version} is below minimum required version #{sdk_version_min}. " \
                    "Some features may not work correctly. Please upgrade the SDK.")
      end

      # Check recommended version
      sdk_version_recommended = metadata['sdkVersionRecommended'] || metadata[:sdkVersionRecommended]
      warned_about_recommended = false
      if sdk_version_recommended && Utils::Version.less_than?(current_version, sdk_version_recommended)
        log(:warn, "SDK version #{current_version} is below recommended version #{sdk_version_recommended}. " \
                   "Consider upgrading for the best experience.")
        warned_about_recommended = true
      end

      # Log if a newer version is available (info level, not a warning)
      # Only log if we haven't already warned about recommended
      sdk_version_latest = metadata['sdkVersionLatest'] || metadata[:sdkVersionLatest]
      if sdk_version_latest &&
         Utils::Version.less_than?(current_version, sdk_version_latest) &&
         !warned_about_recommended
        log(:info, "SDK version #{current_version} - a newer version #{sdk_version_latest} is available.")
      end
    end

    def start_background_tasks
      @polling_manager.start
      @event_queue&.start
    end

    def poll_for_updates(last_update_time)
      params = last_update_time ? { since: last_update_time.utc.iso8601 } : {}
      process_flags_response(@http_client.get('/sdk/updates', params))
    end

    def process_flags_response(response)
      (response['flags'] || []).each do |flag_data|
        cache_flag(FlagState.from_hash(flag_data).key, FlagState.from_hash(flag_data))
      end
    end

    def send_events(events)
      @http_client.post('/sdk/events/batch', { events: events })
    end

    def merge_context(override_context)
      current = @context_mutex.synchronize { @context }
      override_context ? current.merge(override_context) : current
    end

    def get_cached_flag(key)
      return nil unless options.cache_enabled

      @cache.get(key)
    end

    def cache_flag(key, flag)
      @cache.set(key, flag) if options.cache_enabled
    end

    def build_result(key, flag_state, reason)
      EvaluationResult.new(
        flag_key: key, value: flag_state.value, enabled: flag_state.enabled,
        reason: reason, version: flag_state.version
      )
    end

    def log(level, message)
      options.logger&.send(level, "[FlagKit::Client] #{message}")
    end

    def apply_evaluation_jitter
      return unless options.evaluation_jitter_enabled

      sleep(rand(options.evaluation_jitter_min_ms..options.evaluation_jitter_max_ms) / 1000.0)
    end
  end
end
