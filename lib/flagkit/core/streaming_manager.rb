# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module FlagKit
  module Core
    # Connection states for streaming
    module StreamingState
      DISCONNECTED = :disconnected
      CONNECTING = :connecting
      CONNECTED = :connected
      RECONNECTING = :reconnecting
      FAILED = :failed
    end

    # SSE error codes from server
    STREAM_ERROR_CODES = {
      TOKEN_INVALID: 'TOKEN_INVALID',
      TOKEN_EXPIRED: 'TOKEN_EXPIRED',
      SUBSCRIPTION_SUSPENDED: 'SUBSCRIPTION_SUSPENDED',
      CONNECTION_LIMIT: 'CONNECTION_LIMIT',
      STREAMING_UNAVAILABLE: 'STREAMING_UNAVAILABLE'
    }.freeze

    # SSE error event data structure
    class StreamErrorData
      # @return [String] Error code (one of STREAM_ERROR_CODES values)
      attr_reader :code

      # @return [String] Human-readable error message
      attr_reader :message

      # @param code [String] Error code
      # @param message [String] Error message
      def initialize(code:, message:)
        @code = code
        @message = message
      end
    end

    # Streaming configuration
    class StreamingConfig
      attr_reader :enabled, :reconnect_interval, :max_reconnect_attempts, :heartbeat_interval

      def initialize(
        enabled: true,
        reconnect_interval: 3.0,
        max_reconnect_attempts: 3,
        heartbeat_interval: 30.0
      )
        @enabled = enabled
        @reconnect_interval = reconnect_interval
        @max_reconnect_attempts = max_reconnect_attempts
        @heartbeat_interval = heartbeat_interval
      end

      def self.default
        new
      end
    end

    # Manages Server-Sent Events (SSE) connection for real-time flag updates.
    #
    # Security: Uses token exchange pattern to avoid exposing API keys in URLs.
    # 1. Fetches short-lived token via POST with API key in header
    # 2. Connects to SSE endpoint with disposable token in URL
    #
    # Features:
    # - Secure token-based authentication
    # - Automatic token refresh before expiry
    # - Automatic reconnection with exponential backoff
    # - Graceful degradation to polling after max failures
    # - Heartbeat monitoring for connection health
    # - SSE error event handling with appropriate callbacks
    class StreamingManager
      attr_reader :state

      # @param base_url [String] Base URL for API endpoints
      # @param get_api_key [Proc] Callable that returns the current API key
      # @param config [StreamingConfig, nil] Streaming configuration
      # @param on_flag_update [Proc] Callback when flag is updated
      # @param on_flag_delete [Proc] Callback when flag is deleted
      # @param on_flags_reset [Proc] Callback when all flags are reset
      # @param on_fallback_to_polling [Proc] Callback when streaming fails and falls back to polling
      # @param on_subscription_error [Proc, nil] Callback when subscription error occurs (e.g., suspended)
      # @param on_connection_limit_error [Proc, nil] Callback when connection limit is reached
      # @param logger [Object, nil] Logger instance
      def initialize(
        base_url:,
        get_api_key:,
        config: nil,
        on_flag_update:,
        on_flag_delete:,
        on_flags_reset:,
        on_fallback_to_polling:,
        on_subscription_error: nil,
        on_connection_limit_error: nil,
        logger: nil
      )
        @base_url = base_url
        @get_api_key = get_api_key
        @config = config || StreamingConfig.default
        @on_flag_update = on_flag_update
        @on_flag_delete = on_flag_delete
        @on_flags_reset = on_flags_reset
        @on_fallback_to_polling = on_fallback_to_polling
        @on_subscription_error = on_subscription_error
        @on_connection_limit_error = on_connection_limit_error
        @logger = logger

        @state = StreamingState::DISCONNECTED
        @consecutive_failures = 0
        @last_heartbeat = Time.now
        @mutex = Mutex.new
        @stop_requested = false
        @connection_thread = nil
        @token_refresh_thread = nil
        @heartbeat_thread = nil
        @retry_thread = nil
      end

      def connected?
        @state == StreamingState::CONNECTED
      end

      def connect
        @mutex.synchronize do
          return if @state == StreamingState::CONNECTED || @state == StreamingState::CONNECTING

          @state = StreamingState::CONNECTING
          @stop_requested = false
        end

        @connection_thread = Thread.new { initiate_connection }
      end

      def disconnect
        @mutex.synchronize do
          cleanup
          @state = StreamingState::DISCONNECTED
          @consecutive_failures = 0
        end

        @logger&.debug('Streaming disconnected')
      end

      def retry_connection
        @mutex.synchronize do
          return if @state == StreamingState::CONNECTED || @state == StreamingState::CONNECTING

          @consecutive_failures = 0
        end

        connect
      end

      private

      def initiate_connection
        # Step 1: Fetch short-lived stream token
        token_response = fetch_stream_token

        # Step 2: Schedule token refresh at 80% of TTL
        schedule_token_refresh(token_response[:expires_in] * 0.8)

        # Step 3: Create SSE connection with token
        create_connection(token_response[:token])
      rescue StandardError => e
        @logger&.error("Failed to fetch stream token: #{e.message}")
        handle_connection_failure
      end

      def fetch_stream_token
        token_uri = URI("#{@base_url}/sdk/stream/token")

        http = Net::HTTP.new(token_uri.host, token_uri.port)
        http.use_ssl = token_uri.scheme == 'https'

        request = Net::HTTP::Post.new(token_uri.path)
        request['Content-Type'] = 'application/json'
        request['X-API-Key'] = @get_api_key.call
        request.body = '{}'

        response = http.request(request)
        raise "Failed to fetch stream token: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        { token: data['token'], expires_in: data['expiresIn'] }
      end

      def schedule_token_refresh(delay)
        @token_refresh_thread&.kill

        @token_refresh_thread = Thread.new do
          sleep(delay)
          begin
            token_response = fetch_stream_token
            schedule_token_refresh(token_response[:expires_in] * 0.8)
          rescue StandardError => e
            @logger&.warn("Failed to refresh stream token, reconnecting: #{e.message}")
            disconnect
            connect
          end
        end
      end

      def create_connection(token)
        stream_uri = URI("#{@base_url}/sdk/stream?token=#{token}")

        http = Net::HTTP.new(stream_uri.host, stream_uri.port)
        http.use_ssl = stream_uri.scheme == 'https'
        http.read_timeout = nil # No timeout for SSE

        request = Net::HTTP::Get.new(stream_uri)
        request['Accept'] = 'text/event-stream'
        request['Cache-Control'] = 'no-cache'

        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            @logger&.error("SSE connection failed: #{response.code}")
            handle_connection_failure
            return
          end

          handle_open
          read_events(response)
        end
      rescue StandardError => e
        return if @stop_requested

        @logger&.error("SSE connection error: #{e.message}")
        handle_connection_failure
      end

      def handle_open
        @mutex.synchronize do
          @state = StreamingState::CONNECTED
          @consecutive_failures = 0
          @last_heartbeat = Time.now
        end

        start_heartbeat_monitor
        @logger&.info('Streaming connected')
      end

      def read_events(response)
        event_type = nil
        data_buffer = +''

        response.read_body do |chunk|
          return if @stop_requested

          chunk.each_line do |line|
            line = line.strip

            # Empty line = end of event
            if line.empty?
              if event_type && !data_buffer.empty?
                process_event(event_type, data_buffer)
                event_type = nil
                data_buffer = +''
              end
              next
            end

            # Parse SSE format
            if line.start_with?('event:')
              event_type = line[6..].strip
            elsif line.start_with?('data:')
              data_buffer << line[5..].strip
            end
          end
        end

        # Connection closed
        handle_connection_failure if @state == StreamingState::CONNECTED
      end

      def process_event(event_type, data)
        case event_type
        when 'flag_updated'
          flag_data = JSON.parse(data)
          flag = Types::FlagState.new(
            key: flag_data['key'],
            value: flag_data['value'],
            enabled: flag_data['enabled'] || true,
            version: flag_data['version'] || 0,
            flag_type: flag_data['flagType'],
            last_modified: flag_data['lastModified']
          )
          @on_flag_update.call(flag)

        when 'flag_deleted'
          delete_data = JSON.parse(data)
          @on_flag_delete.call(delete_data['key'])

        when 'flags_reset'
          flags_data = JSON.parse(data)
          flags = flags_data.map do |f|
            Types::FlagState.new(
              key: f['key'],
              value: f['value'],
              enabled: f['enabled'] || true,
              version: f['version'] || 0,
              flag_type: f['flagType'],
              last_modified: f['lastModified']
            )
          end
          @on_flags_reset.call(flags)

        when 'heartbeat'
          @mutex.synchronize { @last_heartbeat = Time.now }

        when 'error'
          handle_stream_error(data)
        end
      rescue StandardError => e
        @logger&.warn("Failed to process event #{event_type}: #{e.message}")
      end

      # Handles SSE error events from server.
      #
      # Error codes:
      # - TOKEN_INVALID: Re-authenticate completely
      # - TOKEN_EXPIRED: Refresh token and reconnect
      # - SUBSCRIPTION_SUSPENDED: Notify user, fall back to cached values
      # - CONNECTION_LIMIT: Implement backoff or close other connections
      # - STREAMING_UNAVAILABLE: Fall back to polling
      #
      # @param data [String] JSON error data
      def handle_stream_error(data)
        error_data = JSON.parse(data)
        code = error_data['code']
        message = error_data['message']

        stream_error = StreamErrorData.new(code: code, message: message)

        @logger&.warn("SSE error event received: code=#{code}, message=#{message}")

        case code
        when STREAM_ERROR_CODES[:TOKEN_EXPIRED]
          # Token expired, refresh and reconnect
          @logger&.info('Stream token expired, refreshing...')
          cleanup
          connect # Will fetch new token

        when STREAM_ERROR_CODES[:TOKEN_INVALID]
          # Token is invalid, need full re-authentication
          @logger&.error('Stream token invalid, re-authenticating...')
          cleanup
          connect # Will fetch new token

        when STREAM_ERROR_CODES[:SUBSCRIPTION_SUSPENDED]
          # Subscription issue - notify and fall back
          @logger&.error("Subscription suspended: #{message}")
          @on_subscription_error&.call(message)
          cleanup
          @mutex.synchronize { @state = StreamingState::FAILED }
          @on_fallback_to_polling.call

        when STREAM_ERROR_CODES[:CONNECTION_LIMIT]
          # Too many connections - implement backoff
          @logger&.warn('Connection limit reached, backing off...')
          @on_connection_limit_error&.call
          handle_connection_failure

        when STREAM_ERROR_CODES[:STREAMING_UNAVAILABLE]
          # Streaming not available - fall back to polling
          @logger&.warn('Streaming service unavailable, falling back to polling')
          cleanup
          @mutex.synchronize { @state = StreamingState::FAILED }
          @on_fallback_to_polling.call

        else
          @logger&.warn("Unknown stream error code: #{code}")
          handle_connection_failure
        end
      rescue JSON::ParserError => e
        @logger&.warn("Failed to parse stream error: #{e.message}")
        handle_connection_failure
      end

      def handle_connection_failure
        @mutex.synchronize do
          cleanup
          @consecutive_failures += 1
          failures = @consecutive_failures
          max_attempts = @config.max_reconnect_attempts

          if failures >= max_attempts
            @state = StreamingState::FAILED
            @logger&.warn("Streaming failed, falling back to polling. Failures: #{failures}")
            @on_fallback_to_polling.call
            schedule_streaming_retry
          else
            @state = StreamingState::RECONNECTING
            schedule_reconnect
          end
        end
      end

      def schedule_reconnect
        delay = get_reconnect_delay
        @logger&.debug("Scheduling reconnect in #{delay}s, attempt #{@consecutive_failures}")

        Thread.new do
          sleep(delay)
          connect
        end
      end

      def get_reconnect_delay
        base_delay = @config.reconnect_interval
        backoff = 2**(@consecutive_failures - 1)
        delay = base_delay * backoff
        # Cap at 30 seconds
        [delay, 30.0].min
      end

      def schedule_streaming_retry
        @retry_thread&.kill

        @retry_thread = Thread.new do
          sleep(300) # 5 minutes
          @logger&.info('Retrying streaming connection')
          retry_connection
        end
      end

      def start_heartbeat_monitor
        stop_heartbeat_monitor

        check_interval = @config.heartbeat_interval * 1.5

        @heartbeat_thread = Thread.new do
          sleep(check_interval)

          time_since = Time.now - @last_heartbeat
          threshold = @config.heartbeat_interval * 2

          if time_since > threshold
            @logger&.warn("Heartbeat timeout, reconnecting. Time since: #{time_since}s")
            handle_connection_failure
          else
            start_heartbeat_monitor
          end
        end
      end

      def stop_heartbeat_monitor
        @heartbeat_thread&.kill
        @heartbeat_thread = nil
      end

      def cleanup
        @stop_requested = true
        @connection_thread&.kill
        @connection_thread = nil
        @token_refresh_thread&.kill
        @token_refresh_thread = nil
        stop_heartbeat_monitor
        @retry_thread&.kill
        @retry_thread = nil
      end
    end
  end
end
