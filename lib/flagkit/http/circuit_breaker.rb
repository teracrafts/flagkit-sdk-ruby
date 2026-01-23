# frozen_string_literal: true

module FlagKit
  module Http
    # Circuit breaker pattern implementation for resilient HTTP calls.
    class CircuitBreaker
      # Circuit breaker states
      module State
        CLOSED = :closed
        OPEN = :open
        HALF_OPEN = :half_open
      end

      attr_reader :state, :failure_threshold, :reset_timeout

      # @param failure_threshold [Integer] Number of failures before opening
      # @param reset_timeout [Integer] Seconds to wait before half-open
      def initialize(failure_threshold: 5, reset_timeout: 30)
        @failure_threshold = failure_threshold
        @reset_timeout = reset_timeout
        @state = State::CLOSED
        @failure_count = 0
        @last_failure_time = nil
        @mutex = Mutex.new
      end

      # Checks if the circuit allows requests.
      #
      # @return [Boolean]
      def allow_request?
        @mutex.synchronize do
          case @state
          when State::CLOSED
            true
          when State::OPEN
            check_reset_timeout
            @state != State::OPEN
          when State::HALF_OPEN
            true
          end
        end
      end

      # Records a successful request.
      def record_success
        @mutex.synchronize do
          @failure_count = 0
          @state = State::CLOSED
        end
      end

      # Records a failed request.
      def record_failure
        @mutex.synchronize do
          @failure_count += 1
          @last_failure_time = Time.now

          if @failure_count >= failure_threshold
            @state = State::OPEN
          end
        end
      end

      # Checks if the circuit is open.
      #
      # @return [Boolean]
      def open?
        @mutex.synchronize do
          check_reset_timeout
          @state == State::OPEN
        end
      end

      # Checks if the circuit is closed.
      #
      # @return [Boolean]
      def closed?
        @mutex.synchronize do
          @state == State::CLOSED
        end
      end

      # Checks if the circuit is half-open.
      #
      # @return [Boolean]
      def half_open?
        @mutex.synchronize do
          check_reset_timeout
          @state == State::HALF_OPEN
        end
      end

      # Resets the circuit breaker to closed state.
      def reset
        @mutex.synchronize do
          @state = State::CLOSED
          @failure_count = 0
          @last_failure_time = nil
        end
      end

      # Returns the current failure count.
      #
      # @return [Integer]
      def failure_count
        @mutex.synchronize do
          @failure_count
        end
      end

      # Executes a block with circuit breaker protection.
      #
      # @yield The block to execute
      # @return [Object] The block result
      # @raise [Error] If the circuit is open
      def call
        unless allow_request?
          raise FlagKit::Error.new(ErrorCode::CIRCUIT_OPEN, "Circuit breaker is open")
        end

        begin
          result = yield
          record_success
          result
        rescue StandardError => e
          record_failure
          raise e
        end
      end

      private

      def check_reset_timeout
        return unless @state == State::OPEN && @last_failure_time

        if Time.now - @last_failure_time >= reset_timeout
          @state = State::HALF_OPEN
        end
      end
    end
  end

  # Alias for backward compatibility
  CircuitBreaker = Http::CircuitBreaker
end
