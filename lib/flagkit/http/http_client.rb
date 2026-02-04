# frozen_string_literal: true

require "faraday"
require "json"

module FlagKit
  module Http
    # Usage metrics extracted from response headers.
    #
    # Contains information about API usage limits and subscription status.
    class UsageMetrics
      # @return [Float, nil] Percentage of API call limit used this period (0-150+)
      attr_reader :api_usage_percent

      # @return [Float, nil] Percentage of evaluation limit used (0-150+)
      attr_reader :evaluation_usage_percent

      # @return [Boolean] Whether approaching rate limit threshold
      attr_reader :rate_limit_warning

      # @return [String, nil] Current subscription status: active, trial, past_due, suspended, cancelled
      attr_reader :subscription_status

      VALID_SUBSCRIPTION_STATUSES = %w[active trial past_due suspended cancelled].freeze

      # @param api_usage_percent [Float, nil] API usage percentage
      # @param evaluation_usage_percent [Float, nil] Evaluation usage percentage
      # @param rate_limit_warning [Boolean] Rate limit warning flag
      # @param subscription_status [String, nil] Subscription status
      def initialize(api_usage_percent: nil, evaluation_usage_percent: nil, rate_limit_warning: false, subscription_status: nil)
        @api_usage_percent = api_usage_percent
        @evaluation_usage_percent = evaluation_usage_percent
        @rate_limit_warning = rate_limit_warning
        @subscription_status = subscription_status if subscription_status.nil? || VALID_SUBSCRIPTION_STATUSES.include?(subscription_status)
      end
    end

    # HTTP client with retry logic, circuit breaker integration,
    # request signing, and key rotation support.
    class HttpClient
      BASE_URL = "https://api.flagkit.dev/api/v1"
      BASE_RETRY_DELAY = 1.0
      MAX_RETRY_DELAY = 30.0
      RETRY_MULTIPLIER = 2.0
      JITTER_FACTOR = 0.1

      attr_reader :timeout, :retry_attempts, :circuit_breaker

      # Returns the base URL for the given local port, or the default production URL.
      #
      # @param local_port [Integer, nil] The local port number
      # @return [String] The base URL
      def self.get_base_url(local_port)
        local_port ? "http://localhost:#{local_port}/api/v1" : BASE_URL
      end

      # Returns the currently active API key.
      #
      # @return [String] The current API key
      def api_key
        @current_api_key
      end

      # Returns the key identifier for the current API key.
      #
      # @return [String] The key ID (first 8 characters)
      def key_id
        Utils::Security.get_key_id(@current_api_key)
      end

      # Checks if key rotation is currently active.
      #
      # @return [Boolean] true if within the key rotation grace period
      def in_key_rotation?
        return false unless @key_rotation_timestamp

        elapsed = Time.now - @key_rotation_timestamp
        elapsed < @key_rotation_grace_period
      end

      # @param api_key [String] The API key
      # @param timeout [Integer] Request timeout in seconds
      # @param retry_attempts [Integer] Number of retry attempts
      # @param circuit_breaker [CircuitBreaker] The circuit breaker
      # @param logger [Object, nil] Logger instance
      # @param local_port [Integer, nil] Local development server port
      # @param secondary_api_key [String, nil] Secondary API key for rotation
      # @param key_rotation_grace_period [Integer] Grace period in seconds
      # @param enable_request_signing [Boolean] Enable HMAC-SHA256 request signing
      # @param on_usage_update [Proc, nil] Callback for usage metrics updates
      def initialize(
        api_key:,
        timeout:,
        retry_attempts:,
        circuit_breaker:,
        logger: nil,
        local_port: nil,
        secondary_api_key: nil,
        key_rotation_grace_period: 300,
        enable_request_signing: true,
        on_usage_update: nil
      )
        @base_url = self.class.get_base_url(local_port)
        @primary_api_key = api_key
        @secondary_api_key = secondary_api_key
        @current_api_key = api_key
        @key_rotation_grace_period = key_rotation_grace_period
        @key_rotation_timestamp = nil
        @enable_request_signing = enable_request_signing
        @timeout = timeout
        @retry_attempts = retry_attempts
        @circuit_breaker = circuit_breaker
        @logger = logger
        @on_usage_update = on_usage_update
        @connection = build_connection
      end

      # Makes a GET request.
      #
      # @param path [String] The request path
      # @param params [Hash] Query parameters
      # @return [Hash] The response body
      def get(path, params = {})
        request(:get, path, params: params)
      end

      # Makes a POST request with automatic request signing.
      #
      # @param path [String] The request path
      # @param body [Hash] The request body
      # @return [Hash] The response body
      def post(path, body = {})
        signing_headers = {}

        if @enable_request_signing && !body.empty?
          body_string = body.to_json
          sig_data = Utils::Security.create_request_signature(body_string, @current_api_key)
          signing_headers["X-Signature"] = sig_data[:signature]
          signing_headers["X-Timestamp"] = sig_data[:timestamp].to_s
          signing_headers["X-Key-Id"] = sig_data[:key_id]
        end

        request(:post, path, body: body, extra_headers: signing_headers)
      end

      private

      # Rotates to the secondary API key on authentication failure.
      #
      # @return [Boolean] true if rotation was performed
      def rotate_to_secondary_key
        return false unless @secondary_api_key
        return false if @current_api_key == @secondary_api_key

        log(:info, "Rotating to secondary API key due to authentication failure")
        @current_api_key = @secondary_api_key
        @key_rotation_timestamp = Time.now
        rebuild_connection
        true
      end

      def rebuild_connection
        @connection = build_connection
      end

      def build_connection
        Faraday.new(url: @base_url) do |conn|
          conn.options.timeout = timeout
          conn.options.open_timeout = timeout
          conn.headers["Content-Type"] = "application/json"
          conn.headers["Accept"] = "application/json"
          conn.headers["X-API-Key"] = @current_api_key
          conn.headers["User-Agent"] = "FlagKit-Ruby/#{VERSION}"
          conn.headers["X-FlagKit-SDK-Version"] = VERSION
          conn.headers["X-FlagKit-SDK-Language"] = "ruby"
          conn.adapter Faraday.default_adapter
        end
      end

      def request(method, path, params: nil, body: nil, extra_headers: {})
        unless circuit_breaker.allow_request?
          raise FlagKit::Error.new(ErrorCode::CIRCUIT_OPEN, "Circuit breaker is open")
        end

        attempts = 0
        last_error = nil

        loop do
          attempts += 1
          begin
            response = execute_request(method, path, params, body, extra_headers)
            circuit_breaker.record_success
            return parse_response(response)
          rescue Faraday::TimeoutError => e
            last_error = FlagKit::Error.network_error("Request timed out", cause: e)
          rescue Faraday::ConnectionFailed => e
            last_error = FlagKit::Error.network_error("Connection failed: #{e.message}", cause: e)
          rescue FlagKit::Error => e
            last_error = e

            # Handle 401 errors with key rotation
            if e.code == ErrorCode::AUTH_INVALID_KEY && @secondary_api_key
              if rotate_to_secondary_key
                log(:debug, "Retrying request with secondary API key")
                attempts -= 1 # Don't count rotation retry against attempt limit
                next
              end
            end

            # Don't retry on non-recoverable errors
            raise e unless e.recoverable?
          rescue StandardError => e
            last_error = FlagKit::Error.network_error("Request failed: #{e.message}", cause: e)
          end

          if attempts >= retry_attempts
            circuit_breaker.record_failure
            raise last_error
          end

          sleep(calculate_backoff(attempts))
        end
      end

      def execute_request(method, path, params, body, extra_headers = {})
        @connection.run_request(method, path, body&.to_json, nil) do |req|
          req.params.update(params) if params
          extra_headers.each { |k, v| req.headers[k] = v }
        end
      end

      def parse_response(response)
        # Extract and process usage metrics from headers
        usage_metrics = extract_usage_metrics(response.headers)
        if usage_metrics && @on_usage_update
          @on_usage_update.call(usage_metrics)
        end

        case response.status
        when 200..299
          return {} if response.body.nil? || response.body.empty?

          JSON.parse(response.body)
        when 401
          raise FlagKit::Error.auth_error(ErrorCode::AUTH_INVALID_KEY, "Invalid API key")
        when 403
          raise FlagKit::Error.auth_error(ErrorCode::AUTH_PERMISSION_DENIED, "Permission denied")
        when 404
          raise FlagKit::Error.new(ErrorCode::EVAL_FLAG_NOT_FOUND, "Resource not found")
        when 429
          raise FlagKit::Error.new(ErrorCode::NETWORK_RETRY_LIMIT, "Rate limit exceeded")
        when 500..599
          raise FlagKit::Error.network_error("Server error: #{response.status}")
        else
          raise FlagKit::Error.network_error("Unexpected response status: #{response.status}")
        end
      end

      # Extracts usage metrics from response headers.
      #
      # @param headers [Hash] Response headers
      # @return [UsageMetrics, nil] Usage metrics if any usage headers present
      def extract_usage_metrics(headers)
        api_usage = headers["x-api-usage-percent"]
        eval_usage = headers["x-evaluation-usage-percent"]
        rate_limit_warning = headers["x-rate-limit-warning"]
        subscription_status = headers["x-subscription-status"]

        # Return nil if no usage headers present
        return nil unless api_usage || eval_usage || rate_limit_warning || subscription_status

        api_usage_percent = api_usage ? (Float(api_usage) rescue nil) : nil
        evaluation_usage_percent = eval_usage ? (Float(eval_usage) rescue nil) : nil
        warning_flag = rate_limit_warning == "true"

        # Log warnings for high usage
        if api_usage_percent && api_usage_percent >= 80
          log(:warn, "API usage at #{api_usage_percent}%")
        end
        if evaluation_usage_percent && evaluation_usage_percent >= 80
          log(:warn, "Evaluation usage at #{evaluation_usage_percent}%")
        end
        if subscription_status == "suspended"
          log(:error, "Subscription suspended - service degraded")
        end

        UsageMetrics.new(
          api_usage_percent: api_usage_percent,
          evaluation_usage_percent: evaluation_usage_percent,
          rate_limit_warning: warning_flag,
          subscription_status: subscription_status
        )
      end

      def calculate_backoff(attempt)
        delay = BASE_RETRY_DELAY * (RETRY_MULTIPLIER**(attempt - 1))
        delay = [delay, MAX_RETRY_DELAY].min
        jitter = delay * JITTER_FACTOR * rand
        delay + jitter
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::HttpClient] #{message}")
      end
    end
  end

  # Alias for backward compatibility
  HttpClient = Http::HttpClient
end
