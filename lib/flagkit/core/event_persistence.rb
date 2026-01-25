# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"

module FlagKit
  module Core
    # Crash-resilient event persistence using write-ahead logging (WAL).
    # Events are persisted to disk before being queued for sending to prevent
    # data loss during unexpected process termination.
    class EventPersistence
      # Event status constants
      STATUS_PENDING = "pending"
      STATUS_SENDING = "sending"
      STATUS_SENT = "sent"
      STATUS_FAILED = "failed"

      # Default buffer size before flushing to disk
      DEFAULT_BUFFER_SIZE = 100

      # Default retention period for sent events (24 hours in seconds)
      DEFAULT_RETENTION_PERIOD = 86_400

      attr_reader :storage_path, :max_events, :flush_interval

      # @param storage_path [String] Directory for event storage
      # @param max_events [Integer] Maximum events to persist
      # @param flush_interval [Integer] Milliseconds between disk writes
      # @param logger [Object, nil] Logger instance
      def initialize(storage_path:, max_events:, flush_interval:, logger: nil)
        @storage_path = storage_path
        @max_events = max_events
        @flush_interval = flush_interval
        @logger = logger
        @buffer = []
        @buffer_mutex = Mutex.new
        @file_mutex = Mutex.new
        @closed = false
        @flush_thread = nil
        @buffer_size = DEFAULT_BUFFER_SIZE

        ensure_storage_directory
        start_flush_thread
      end

      # Persists an event to the buffer.
      # Events are written to disk when the buffer is full or on flush interval.
      #
      # @param event [Hash] The event to persist
      # @return [String] The event ID
      def persist(event)
        return nil if @closed

        event_id = event[:id] || event["id"] || generate_event_id
        persisted_event = {
          id: event_id,
          type: event[:type] || event["type"],
          data: event[:data] || event["data"],
          timestamp: event[:timestamp] || event["timestamp"] || (Time.now.to_f * 1000).to_i,
          status: STATUS_PENDING
        }

        should_flush = false

        @buffer_mutex.synchronize do
          @buffer << persisted_event
          should_flush = @buffer.size >= @buffer_size
        end

        flush if should_flush

        event_id
      end

      # Flushes buffered events to disk with file locking.
      #
      # @return [Boolean] Whether the flush was successful
      def flush
        events_to_write = nil

        @buffer_mutex.synchronize do
          return true if @buffer.empty?

          events_to_write = @buffer.dup
          @buffer.clear
        end

        write_events_to_disk(events_to_write)
      rescue StandardError => e
        log(:error, "Failed to flush events to disk: #{e.message}")
        # Re-add events to buffer on failure
        @buffer_mutex.synchronize do
          @buffer = events_to_write + @buffer
        end
        false
      end

      # Marks events as sent after successful batch send.
      #
      # @param event_ids [Array<String>] IDs of events to mark as sent
      # @return [Boolean] Whether the operation was successful
      def mark_sent(event_ids)
        return true if event_ids.empty?

        update_event_status(event_ids, STATUS_SENT, sent_at: (Time.now.to_f * 1000).to_i)
      end

      # Marks events as sending (in-flight).
      #
      # @param event_ids [Array<String>] IDs of events to mark as sending
      # @return [Boolean] Whether the operation was successful
      def mark_sending(event_ids)
        return true if event_ids.empty?

        update_event_status(event_ids, STATUS_SENDING)
      end

      # Marks events as pending (e.g., after failed send).
      #
      # @param event_ids [Array<String>] IDs of events to mark as pending
      # @return [Boolean] Whether the operation was successful
      def mark_pending(event_ids)
        return true if event_ids.empty?

        update_event_status(event_ids, STATUS_PENDING)
      end

      # Recovers pending and sending events on startup.
      # Events marked as "sending" are treated as crashed mid-send and recovered.
      #
      # @return [Array<Hash>] Recovered events
      def recover
        recovered_events = []

        @file_mutex.synchronize do
          event_files.each do |file_path|
            events_by_id = {}

            with_file_lock(file_path, File::LOCK_SH) do |file|
              file.each_line do |line|
                next if line.strip.empty?

                begin
                  event = JSON.parse(line.strip, symbolize_names: true)

                  # Handle status update entries
                  if event[:status] && event[:id] && !event[:type]
                    if events_by_id[event[:id]]
                      events_by_id[event[:id]][:status] = event[:status]
                    end
                  else
                    events_by_id[event[:id]] = event
                  end
                rescue JSON::ParserError => e
                  log(:warn, "Skipping corrupted event line: #{e.message}")
                end
              end
            end

            # Collect pending and sending (crashed mid-send) events
            events_by_id.each_value do |event|
              if [STATUS_PENDING, STATUS_SENDING].include?(event[:status])
                recovered_events << event
              end
            end
          end
        end

        log(:info, "Recovered #{recovered_events.size} pending events") unless recovered_events.empty?
        recovered_events
      rescue StandardError => e
        log(:error, "Failed to recover events: #{e.message}")
        []
      end

      # Cleans up old sent events and compacts files.
      #
      # @param retention_period [Integer] Seconds to keep sent events (default: 24 hours)
      # @return [Integer] Number of events cleaned up
      def cleanup(retention_period: DEFAULT_RETENTION_PERIOD)
        cleaned_count = 0
        cutoff_time = (Time.now.to_f * 1000).to_i - (retention_period * 1000)

        @file_mutex.synchronize do
          event_files.each do |file_path|
            events_to_keep = []
            events_cleaned = 0

            with_file_lock(file_path, File::LOCK_EX) do |file|
              events_by_id = {}

              file.each_line do |line|
                next if line.strip.empty?

                begin
                  event = JSON.parse(line.strip, symbolize_names: true)

                  if event[:status] && event[:id] && !event[:type]
                    # Status update
                    if events_by_id[event[:id]]
                      events_by_id[event[:id]][:status] = event[:status]
                      events_by_id[event[:id]][:sent_at] = event[:sent_at] if event[:sent_at]
                    end
                  else
                    events_by_id[event[:id]] = event
                  end
                rescue JSON::ParserError
                  next
                end
              end

              # Keep events that are not sent or were sent recently
              events_by_id.each_value do |event|
                if event[:status] == STATUS_SENT
                  # Clean up if: no sent_at (legacy), retention_period is 0, or sent_at is before cutoff
                  if !event[:sent_at] || retention_period == 0 || event[:sent_at] <= cutoff_time
                    events_cleaned += 1
                  else
                    events_to_keep << event
                  end
                elsif event[:status] == STATUS_FAILED
                  events_cleaned += 1
                else
                  events_to_keep << event
                end
              end
            end

            # Rewrite file with kept events only
            if events_cleaned > 0
              File.open(file_path, "w") do |file|
                file.flock(File::LOCK_EX)
                events_to_keep.each do |event|
                  file.puts(JSON.generate(event))
                end
                file.flush
                file.fsync
                file.flock(File::LOCK_UN)
              end
              cleaned_count += events_cleaned
            end

            # Delete empty files
            File.delete(file_path) if File.exist?(file_path) && File.size(file_path) == 0
          end
        end

        log(:debug, "Cleaned up #{cleaned_count} old events") if cleaned_count > 0
        cleaned_count
      rescue StandardError => e
        log(:error, "Failed to cleanup events: #{e.message}")
        0
      end

      # Flushes remaining events and cleans up resources.
      def close
        return if @closed

        @closed = true
        stop_flush_thread
        flush
        cleanup
      end

      # Returns the total count of pending events (in buffer and on disk).
      #
      # @return [Integer]
      def pending_count
        buffer_count = @buffer_mutex.synchronize { @buffer.size }
        disk_count = count_events_by_status([STATUS_PENDING, STATUS_SENDING])
        buffer_count + disk_count
      end

      private

      def ensure_storage_directory
        FileUtils.mkdir_p(@storage_path) unless File.directory?(@storage_path)
        # Set restrictive permissions (owner only)
        File.chmod(0o700, @storage_path)
      rescue StandardError => e
        log(:error, "Failed to create storage directory: #{e.message}")
        raise
      end

      def start_flush_thread
        return if @flush_interval <= 0

        @flush_thread = Thread.new do
          interval_seconds = @flush_interval / 1000.0

          until @closed
            sleep(interval_seconds)
            break if @closed

            flush
          end
        end
      end

      def stop_flush_thread
        @flush_thread&.kill
        @flush_thread = nil
      end

      def generate_event_id
        "evt_#{SecureRandom.hex(12)}"
      end

      def current_log_file
        # Use a single file per day to avoid too many small files
        date_str = Time.now.strftime("%Y%m%d")
        File.join(@storage_path, "flagkit-events-#{date_str}.jsonl")
      end

      def event_files
        Dir.glob(File.join(@storage_path, "flagkit-events-*.jsonl")).sort
      end

      def lock_file_path
        File.join(@storage_path, "flagkit-events.lock")
      end

      def write_events_to_disk(events)
        return true if events.empty?

        # Check if we would exceed max events
        current_count = count_events_by_status([STATUS_PENDING, STATUS_SENDING])
        if current_count + events.size > @max_events
          # Remove oldest events to make room
          excess = (current_count + events.size) - @max_events
          log(:warn, "Dropping #{excess} oldest events to stay within max_events limit")
          remove_oldest_events(excess)
        end

        file_path = current_log_file

        @file_mutex.synchronize do
          with_file_lock(file_path, File::LOCK_EX, create: true) do |file|
            events.each do |event|
              file.puts(JSON.generate(event))
            end
            file.flush
            file.fsync
          end
        end

        true
      rescue StandardError => e
        log(:error, "Failed to write events to disk: #{e.message}")
        false
      end

      def update_event_status(event_ids, new_status, extra_fields = {})
        event_ids_set = event_ids.to_set
        timestamp = (Time.now.to_f * 1000).to_i

        @file_mutex.synchronize do
          event_files.each do |file_path|
            updates_needed = []

            # First pass: find events that need updating
            with_file_lock(file_path, File::LOCK_SH) do |file|
              file.each_line do |line|
                next if line.strip.empty?

                begin
                  event = JSON.parse(line.strip, symbolize_names: true)
                  if event_ids_set.include?(event[:id]) && event[:type]
                    updates_needed << event[:id]
                  end
                rescue JSON::ParserError
                  next
                end
              end
            end

            # Second pass: append status updates
            next if updates_needed.empty?

            with_file_lock(file_path, File::LOCK_EX) do |file|
              file.seek(0, IO::SEEK_END)
              updates_needed.each do |event_id|
                status_update = { id: event_id, status: new_status }.merge(extra_fields)
                file.puts(JSON.generate(status_update))
              end
              file.flush
              file.fsync
            end
          end
        end

        true
      rescue StandardError => e
        log(:error, "Failed to update event status: #{e.message}")
        false
      end

      def count_events_by_status(statuses)
        count = 0
        statuses_set = statuses.to_set

        event_files.each do |file_path|
          events_by_id = {}

          with_file_lock(file_path, File::LOCK_SH) do |file|
            file.each_line do |line|
              next if line.strip.empty?

              begin
                event = JSON.parse(line.strip, symbolize_names: true)

                if event[:status] && event[:id] && !event[:type]
                  events_by_id[event[:id]][:status] = event[:status] if events_by_id[event[:id]]
                else
                  events_by_id[event[:id]] = event
                end
              rescue JSON::ParserError
                next
              end
            end
          end

          events_by_id.each_value do |event|
            count += 1 if statuses_set.include?(event[:status])
          end
        end

        count
      rescue StandardError
        0
      end

      def remove_oldest_events(count)
        removed = 0
        sorted_files = event_files.sort # Oldest first by filename

        sorted_files.each do |file_path|
          break if removed >= count

          events_to_keep = []

          with_file_lock(file_path, File::LOCK_EX) do |file|
            events = []

            file.each_line do |line|
              next if line.strip.empty?

              begin
                event = JSON.parse(line.strip, symbolize_names: true)
                if event[:type] && [STATUS_PENDING, STATUS_SENDING].include?(event[:status])
                  events << event
                end
              rescue JSON::ParserError
                next
              end
            end

            # Sort by timestamp and remove oldest
            events.sort_by! { |e| e[:timestamp] || 0 }
            to_remove = [count - removed, events.size].min
            removed += to_remove
            events_to_keep = events.drop(to_remove)
          end

          # Rewrite file
          File.open(file_path, "w") do |file|
            file.flock(File::LOCK_EX)
            events_to_keep.each do |event|
              file.puts(JSON.generate(event))
            end
            file.flush
            file.fsync
            file.flock(File::LOCK_UN)
          end
        end

        removed
      end

      def with_file_lock(file_path, lock_mode, create: false)
        mode = create ? "a+" : "r+"

        # Create file if it doesn't exist when in create mode
        if create && !File.exist?(file_path)
          FileUtils.touch(file_path)
          File.chmod(0o600, file_path)
        end

        return unless File.exist?(file_path)

        File.open(file_path, mode) do |file|
          file.flock(lock_mode)
          begin
            file.seek(0) if lock_mode == File::LOCK_SH || mode == "r+"
            yield file
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::EventPersistence] #{message}")
      end
    end
  end

  # Alias for backward compatibility
  EventPersistence = Core::EventPersistence
end
