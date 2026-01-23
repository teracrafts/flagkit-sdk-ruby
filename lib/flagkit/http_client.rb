# frozen_string_literal: true

require "faraday"
require "json"

module FlagKit
  # HTTP client with retry logic and circuit breaker integration.
  class HttpClient
    BASE_RETRY_DELAY = 1.0
    MAX_RETRY_DELAY = 30.0
    RETRY_MULTIPLIER = 2.0
    JITTER_FACTOR = 0.1

    attr_reader :base_url, :api_key, :timeout, :retry_attempts, :circuit_breaker

    # @param base_url [String] The base URL
    # @param api_key [String] The API key
    # @param timeout [Integer] Request timeout in seconds
    # @param retry_attempts [Integer] Number of retry attempts
    # @param circuit_breaker [CircuitBreaker] The circuit breaker
    # @param logger [Object, nil] Logger instance
    def initialize(base_url:, api_key:, timeout:, retry_attempts:, circuit_breaker:, logger: nil)
      @base_url = base_url.chomp("/")
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
      Faraday.new(url: base_url) do |conn|
        conn.options.timeout = timeout
        conn.options.open_timeout = timeout
        conn.headers["Content-Type"] = "application/json"
        conn.headers["Accept"] = "application/json"
        conn.headers["Authorization"] = "Bearer #{api_key}"
        conn.headers["User-Agent"] = "FlagKit-Ruby/#{VERSION}"
        conn.adapter Faraday.default_adapter
      end
    end

    def request(method, path, params: nil, body: nil)
      unless circuit_breaker.allow_request?
        raise Error.new(ErrorCode::CIRCUIT_OPEN, "Circuit breaker is open")
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
          last_error = Error.network_error("Request timed out", cause: e)
        rescue Faraday::ConnectionFailed => e
          last_error = Error.network_error("Connection failed: #{e.message}", cause: e)
        rescue Error => e
          last_error = e
          # Don't retry on non-recoverable errors
          raise e unless e.recoverable?
        rescue StandardError => e
          last_error = Error.network_error("Request failed: #{e.message}", cause: e)
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
        raise Error.auth_error(ErrorCode::AUTH_INVALID_KEY, "Invalid API key")
      when 403
        raise Error.auth_error(ErrorCode::AUTH_PERMISSION_DENIED, "Permission denied")
      when 404
        raise Error.new(ErrorCode::EVAL_FLAG_NOT_FOUND, "Resource not found")
      when 429
        raise Error.new(ErrorCode::NETWORK_RETRY_LIMIT, "Rate limit exceeded")
      when 500..599
        raise Error.network_error("Server error: #{response.status}")
      else
        raise Error.network_error("Unexpected response status: #{response.status}")
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
