# frozen_string_literal: true

module FlagKit
  module Core
    # Batches and sends analytics events.
    class EventQueue
      attr_reader :batch_size, :flush_interval, :running, :persistence

      # @param batch_size [Integer] Maximum events per batch
      # @param flush_interval [Integer] Seconds between flushes
      # @param on_flush [Proc] Callback to send events
      # @param logger [Object, nil] Logger instance
      # @param persist_events [Boolean] Enable crash-resilient event persistence
      # @param event_storage_path [String, nil] Directory for event storage
      # @param max_persisted_events [Integer] Maximum events to persist
      # @param persistence_flush_interval [Integer] Milliseconds between disk writes
      def initialize(
        batch_size:,
        flush_interval:,
        on_flush:,
        logger: nil,
        persist_events: false,
        event_storage_path: nil,
        max_persisted_events: 10_000,
        persistence_flush_interval: 1000
      )
        @batch_size = batch_size
        @flush_interval = flush_interval
        @on_flush = on_flush
        @logger = logger
        @queue = []
        @mutex = Mutex.new
        @running = false
        @thread = nil
        @persist_events = persist_events
        @persistence = nil

        setup_persistence(event_storage_path, max_persisted_events, persistence_flush_interval) if persist_events
      end

      # Starts the background flush thread.
      def start
        @mutex.synchronize do
          return if @running

          @running = true
          @thread = Thread.new { flush_loop }
        end

        # Recover persisted events on start
        recover_persisted_events if @persist_events && @persistence
      end

      # Stops the background flush thread.
      def stop
        @mutex.synchronize do
          @running = false
        end
        @thread&.join(5)
        @thread = nil
        flush
        @persistence&.close
      end

      # Adds an event to the queue.
      #
      # @param event [Hash] The event to queue
      def enqueue(event)
        # Persist event BEFORE queuing (crash-safe)
        if @persist_events && @persistence
          event_id = @persistence.persist(event)
          event = event.merge(id: event_id) if event_id
        end

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

        # Mark events as sending if persistence is enabled
        event_ids = events.map { |e| e[:id] || e["id"] }.compact
        @persistence&.mark_sending(event_ids) if @persist_events && event_ids.any?

        begin
          @on_flush.call(events)

          # Mark events as sent on success
          @persistence&.mark_sent(event_ids) if @persist_events && event_ids.any?
        rescue StandardError => e
          log(:error, "Failed to send events: #{e.message}")

          # Mark events as pending on failure (will retry)
          @persistence&.mark_pending(event_ids) if @persist_events && event_ids.any?

          # Re-queue events on failure
          @mutex.synchronize do
            @queue = events + @queue
          end
        end
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::EventQueue] #{message}")
      end

      def setup_persistence(storage_path, max_events, flush_interval)
        return unless storage_path

        @persistence = EventPersistence.new(
          storage_path: storage_path,
          max_events: max_events,
          flush_interval: flush_interval,
          logger: @logger
        )
      rescue StandardError => e
        log(:error, "Failed to setup event persistence: #{e.message}")
        @persist_events = false
        @persistence = nil
      end

      def recover_persisted_events
        return unless @persistence

        recovered = @persistence.recover
        return if recovered.empty?

        log(:info, "Recovering #{recovered.size} persisted events")

        # Add recovered events to the front of the queue with priority
        @mutex.synchronize do
          @queue = recovered + @queue
        end
      rescue StandardError => e
        log(:error, "Failed to recover persisted events: #{e.message}")
      end
    end
  end

  # Alias for backward compatibility
  EventQueue = Core::EventQueue
end
