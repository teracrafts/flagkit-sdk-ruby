# frozen_string_literal: true

module FlagKit
  module Core
    # Batches and sends analytics events.
    class EventQueue
      attr_reader :batch_size, :flush_interval, :running

      # @param batch_size [Integer] Maximum events per batch
      # @param flush_interval [Integer] Seconds between flushes
      # @param on_flush [Proc] Callback to send events
      # @param logger [Object, nil] Logger instance
      def initialize(batch_size:, flush_interval:, on_flush:, logger: nil)
        @batch_size = batch_size
        @flush_interval = flush_interval
        @on_flush = on_flush
        @logger = logger
        @queue = []
        @mutex = Mutex.new
        @running = false
        @thread = nil
      end

      # Starts the background flush thread.
      def start
        @mutex.synchronize do
          return if @running

          @running = true
          @thread = Thread.new { flush_loop }
        end
      end

      # Stops the background flush thread.
      def stop
        @mutex.synchronize do
          @running = false
        end
        @thread&.join(5)
        @thread = nil
        flush
      end

      # Adds an event to the queue.
      #
      # @param event [Hash] The event to queue
      def enqueue(event)
        should_flush = false

        @mutex.synchronize do
          @queue << event
          should_flush = @queue.size >= batch_size
        end

        flush if should_flush
      end

      # Flushes all pending events.
      def flush
        events = nil

        @mutex.synchronize do
          return if @queue.empty?

          events = @queue.dup
          @queue.clear
        end

        send_events(events)
      end

      # Returns the number of pending events.
      #
      # @return [Integer]
      def size
        @mutex.synchronize { @queue.size }
      end

      # Checks if the queue is running.
      #
      # @return [Boolean]
      def running?
        @mutex.synchronize { @running }
      end

      private

      def flush_loop
        while running?
          sleep(flush_interval)
          break unless running?

          flush
        end
      end

      def send_events(events)
        return if events.nil? || events.empty?

        @on_flush.call(events)
      rescue StandardError => e
        log(:error, "Failed to send events: #{e.message}")
        # Re-queue events on failure
        @mutex.synchronize do
          @queue = events + @queue
        end
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::EventQueue] #{message}")
      end
    end
  end

  # Alias for backward compatibility
  EventQueue = Core::EventQueue
end
