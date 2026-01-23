# frozen_string_literal: true

module FlagKit
  module Core
    # Manages background polling for flag updates.
    class PollingManager
      MAX_BACKOFF_MULTIPLIER = 4

      attr_reader :interval, :running

      # @param interval [Integer] Polling interval in seconds
      # @param on_update [Proc] Callback when updates are received
      # @param logger [Object, nil] Logger instance
      def initialize(interval:, on_update:, logger: nil)
        @interval = interval
        @on_update = on_update
        @logger = logger
        @running = false
        @last_update_time = nil
        @consecutive_errors = 0
        @mutex = Mutex.new
        @thread = nil
      end

      # Starts the polling loop.
      def start
        @mutex.synchronize do
          return if @running

          @running = true
          @thread = Thread.new { polling_loop }
        end
      end

      # Stops the polling loop.
      def stop
        @mutex.synchronize do
          @running = false
        end
        @thread&.join(5)
        @thread = nil
      end

      # Checks if polling is running.
      #
      # @return [Boolean]
      def running?
        @mutex.synchronize { @running }
      end

      # Gets the last update timestamp.
      #
      # @return [Time, nil]
      def last_update_time
        @mutex.synchronize { @last_update_time }
      end

      # Manually triggers a poll.
      #
      # @return [Boolean] Whether the poll was successful
      def poll_now
        perform_poll
      end

      private

      def polling_loop
        while running?
          sleep(current_interval_with_jitter)
          break unless running?

          perform_poll
        end
      end

      def perform_poll
        @on_update.call(@last_update_time)
        @mutex.synchronize do
          @last_update_time = Time.now
          @consecutive_errors = 0
        end
        true
      rescue StandardError => e
        @mutex.synchronize do
          @consecutive_errors += 1
        end
        log(:error, "Polling failed: #{e.message}")
        false
      end

      def current_interval_with_jitter
        base = interval * backoff_multiplier
        jitter = base * 0.1 * rand
        base + jitter
      end

      def backoff_multiplier
        errors = @mutex.synchronize { @consecutive_errors }
        [2**errors, MAX_BACKOFF_MULTIPLIER].min
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::PollingManager] #{message}")
      end
    end
  end

  # Alias for backward compatibility
  PollingManager = Core::PollingManager
end
