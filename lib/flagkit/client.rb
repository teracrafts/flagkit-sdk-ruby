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

      @circuit_breaker = CircuitBreaker.new(
        failure_threshold: options.circuit_breaker_threshold,
        reset_timeout: options.circuit_breaker_reset_timeout
      )

      @http_client = HttpClient.new(
        api_key: options.api_key,
        timeout: options.timeout,
        retry_attempts: options.retry_attempts,
        circuit_breaker: @circuit_breaker,
        logger: options.logger
      )

      @cache = Cache.new(
        ttl: options.cache_ttl,
        max_size: options.max_cache_size
      )

      @polling_manager = PollingManager.new(
        interval: options.polling_interval,
        on_update: method(:poll_for_updates),
        logger: options.logger
      )

      @event_queue = EventQueue.new(
        batch_size: options.event_batch_size,
        flush_interval: options.event_flush_interval,
        on_flush: method(:send_events),
        logger: options.logger
      ) if options.events_enabled
    end

    # Initializes the SDK by fetching initial flag state.
    def initialize_sdk
      load_bootstrap if options.bootstrap
      fetch_initial_flags
      start_background_tasks
      mark_ready
    rescue StandardError => e
      log(:error, "Failed to initialize SDK: #{e.message}")
      mark_ready # Mark ready even on failure to unblock waiters
      raise Error.init_error("Failed to initialize: #{e.message}")
    end

    # Waits for the SDK to be ready.
    #
    # @param timeout [Integer, nil] Maximum time to wait in seconds
    # @return [Boolean] Whether the SDK is ready
    def wait_for_ready(timeout: nil)
      @ready_mutex.synchronize do
        return true if @ready

        if timeout
          @ready_condition.wait(@ready_mutex, timeout)
        else
          @ready_condition.wait(@ready_mutex) until @ready
        end
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
      @context_mutex.synchronize do
        @context = EvaluationContext.new
      end
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
      effective_context = merge_context(context)

      # Check cache first
      if options.cache_enabled
        cached = get_cached_flag(key)
        if cached
          return build_result(key, cached, EvaluationReason::CACHED)
        end
      end

      # Fetch from server
      begin
        response = @http_client.post("/sdk/evaluate", {
          key: key,
          context: effective_context.strip_private_attributes.to_h
        })

        flag_state = FlagState.from_hash(response)
        cache_flag(key, flag_state) if options.cache_enabled
        build_result(key, flag_state, EvaluationReason::SERVER)
      rescue Error => e
        log(:warn, "Evaluation failed for #{key}: #{e.message}")
        EvaluationResult.default_result(key, default_value, EvaluationReason::ERROR)
      end
    end

    # Gets a boolean flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Boolean] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Boolean]
    def get_boolean_value(key, default_value, context: nil)
      result = evaluate(key, default_value, context: context)
      result.boolean_value
    end

    # Gets a string flag value.
    #
    # @param key [String] The flag key
    # @param default_value [String] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [String, nil]
    def get_string_value(key, default_value, context: nil)
      result = evaluate(key, default_value, context: context)
      result.string_value || default_value
    end

    # Gets a number flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Float] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Float]
    def get_number_value(key, default_value, context: nil)
      result = evaluate(key, default_value, context: context)
      result.number_value
    end

    # Gets an integer flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Integer] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Integer]
    def get_int_value(key, default_value, context: nil)
      result = evaluate(key, default_value, context: context)
      result.int_value
    end

    # Gets a JSON flag value.
    #
    # @param key [String] The flag key
    # @param default_value [Hash] The default value
    # @param context [EvaluationContext, nil] Optional context override
    # @return [Hash, nil]
    def get_json_value(key, default_value, context: nil)
      result = evaluate(key, default_value, context: context)
      result.json_value || default_value
    end

    # Tracks an analytics event.
    #
    # @param event_type [String] The event type
    # @param data [Hash, nil] Optional event data
    def track(event_type, data = nil)
      return unless options.events_enabled && @event_queue

      current_context = context
      event = {
        type: event_type,
        timestamp: Time.now.utc.iso8601,
        userId: current_context.user_id,
        data: data
      }.compact

      @event_queue.enqueue(event)
    end

    # Closes the client and releases resources.
    def close
      @polling_manager.stop
      @event_queue&.stop
      @cache.clear
      log(:info, "Client closed")
    end

    private

    def mark_ready
      @ready_mutex.synchronize do
        @ready = true
        @ready_condition.broadcast
      end
    end

    def load_bootstrap
      return unless options.bootstrap.is_a?(Hash)

      flags = options.bootstrap["flags"] || options.bootstrap[:flags] || []
      flags.each do |flag_data|
        flag = FlagState.from_hash(flag_data)
        cache_flag(flag.key, flag)
      end
    end

    def fetch_initial_flags
      response = @http_client.get("/sdk/init")
      flags = response["flags"] || []
      flags.each do |flag_data|
        flag = FlagState.from_hash(flag_data)
        cache_flag(flag.key, flag)
      end
    rescue Error => e
      log(:warn, "Failed to fetch initial flags: #{e.message}")
      # Continue without initial flags - will use cache/defaults
    end

    def start_background_tasks
      @polling_manager.start
      @event_queue&.start
    end

    def poll_for_updates(last_update_time)
      params = {}
      params[:since] = last_update_time.utc.iso8601 if last_update_time

      response = @http_client.get("/sdk/updates", params)
      flags = response["flags"] || []
      flags.each do |flag_data|
        flag = FlagState.from_hash(flag_data)
        cache_flag(flag.key, flag)
      end
    end

    def send_events(events)
      @http_client.post("/sdk/events/batch", { events: events })
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
      return unless options.cache_enabled

      @cache.set(key, flag)
    end

    def build_result(key, flag_state, reason)
      EvaluationResult.new(
        flag_key: key,
        value: flag_state.value,
        enabled: flag_state.enabled,
        reason: reason,
        version: flag_state.version
      )
    end

    def log(level, message)
      return unless options.logger

      options.logger.send(level, "[FlagKit::Client] #{message}")
    end
  end
end
