# frozen_string_literal: true

require "faraday"
require "json"

module FlagKit
  module Http
    # HTTP client with retry logic and circuit breaker integration.
    class HttpClient
      BASE_URL = "https://api.flagkit.dev/api/v1"
      BASE_RETRY_DELAY = 1.0
      MAX_RETRY_DELAY = 30.0
      RETRY_MULTIPLIER = 2.0
      JITTER_FACTOR = 0.1

      attr_reader :api_key, :timeout, :retry_attempts, :circuit_breaker

      # Returns the base URL for the given local port, or the default production URL.
      #
      # @param local_port [Integer, nil] The local port number
      # @return [String] The base URL
      def self.get_base_url(local_port)
        local_port ? "http://localhost:#{local_port}/api/v1" : BASE_URL
      end

      # @param api_key [String] The API key
      # @param timeout [Integer] Request timeout in seconds
      # @param retry_attempts [Integer] Number of retry attempts
      # @param circuit_breaker [CircuitBreaker] The circuit breaker
      # @param logger [Object, nil] Logger instance
      # @param local_port [Integer, nil] Local development server port
      def initialize(api_key:, timeout:, retry_attempts:, circuit_breaker:, logger: nil, local_port: nil)
        @base_url = self.class.get_base_url(local_port)
        @api_key = api_key
        @timeout = timeout
        @retry_attempts = retry_attempts
        @circuit_breaker = circuit_breaker
        @logger = logger
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

      # Makes a POST request.
      #
      # @param path [String] The request path
      # @param body [Hash] The request body
      # @return [Hash] The response body
      def post(path, body = {})
        request(:post, path, body: body)
      end

      private

      def build_connection
        Faraday.new(url: @base_url) do |conn|
          conn.options.timeout = timeout
          conn.options.open_timeout = timeout
          conn.headers["Content-Type"] = "application/json"
          conn.headers["Accept"] = "application/json"
          conn.headers["X-API-Key"] = api_key
          conn.headers["User-Agent"] = "FlagKit-Ruby/#{VERSION}"
          conn.adapter Faraday.default_adapter
        end
      end

      def request(method, path, params: nil, body: nil)
        unless circuit_breaker.allow_request?
          raise FlagKit::Error.new(ErrorCode::CIRCUIT_OPEN, "Circuit breaker is open")
        end

        attempts = 0
        last_error = nil

        loop do
          attempts += 1
          begin
            response = execute_request(method, path, params, body)
            circuit_breaker.record_success
            return parse_response(response)
          rescue Faraday::TimeoutError => e
            last_error = FlagKit::Error.network_error("Request timed out", cause: e)
          rescue Faraday::ConnectionFailed => e
            last_error = FlagKit::Error.network_error("Connection failed: #{e.message}", cause: e)
          rescue FlagKit::Error => e
            last_error = e
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

      def execute_request(method, path, params, body)
        @connection.run_request(method, path, body&.to_json, nil) do |req|
          req.params.update(params) if params
        end
      end

      def parse_response(response)
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
