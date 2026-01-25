# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe FlagKit::Core::EventPersistence do
  let(:storage_path) { Dir.mktmpdir("flagkit-test-events") }
  let(:max_events) { 1000 }
  let(:flush_interval) { 100 } # 100ms for faster tests
  let(:logger) { nil }

  let(:persistence) do
    described_class.new(
      storage_path: storage_path,
      max_events: max_events,
      flush_interval: flush_interval,
      logger: logger
    )
  end

  after do
    persistence.close
    FileUtils.rm_rf(storage_path) if File.directory?(storage_path)
  end

  describe "#initialize" do
    it "creates the storage directory" do
      expect(File.directory?(storage_path)).to be true
    end

    it "sets configuration values" do
      expect(persistence.storage_path).to eq(storage_path)
      expect(persistence.max_events).to eq(max_events)
      expect(persistence.flush_interval).to eq(flush_interval)
    end

    it "sets restrictive permissions on storage directory" do
      mode = File.stat(storage_path).mode & 0o777
      expect(mode).to eq(0o700)
    end
  end

  describe "#persist" do
    it "returns an event ID" do
      event = { type: "test", data: { key: "value" } }
      event_id = persistence.persist(event)

      expect(event_id).to match(/^evt_[a-f0-9]{24}$/)
    end

    it "uses provided event ID if present" do
      event = { id: "custom_id_123", type: "test", data: {} }
      event_id = persistence.persist(event)

      expect(event_id).to eq("custom_id_123")
    end

    it "adds event to buffer" do
      persistence.persist({ type: "test", data: {} })

      expect(persistence.pending_count).to be >= 1
    end

    it "returns nil when persistence is closed" do
      persistence.close

      expect(persistence.persist({ type: "test" })).to be_nil
    end
  end

  describe "#flush" do
    it "writes buffered events to disk" do
      persistence.persist({ type: "event1", data: { foo: "bar" } })
      persistence.persist({ type: "event2", data: { baz: "qux" } })

      persistence.flush

      # Read the event file
      event_files = Dir.glob(File.join(storage_path, "flagkit-events-*.jsonl"))
      expect(event_files).not_to be_empty

      content = File.read(event_files.first)
      lines = content.lines.reject(&:empty?)

      expect(lines.size).to eq(2)
      expect(lines[0]).to include("event1")
      expect(lines[1]).to include("event2")
    end

    it "clears the buffer after flush" do
      persistence.persist({ type: "test" })
      persistence.flush

      # Buffer should be cleared (pending_count only from disk now)
      buffer_count = persistence.instance_variable_get(:@buffer).size
      expect(buffer_count).to eq(0)
    end

    it "returns true when buffer is empty" do
      expect(persistence.flush).to be true
    end
  end

  describe "#mark_sent" do
    it "marks events as sent" do
      event_id = persistence.persist({ type: "test" })
      persistence.flush

      result = persistence.mark_sent([event_id])

      expect(result).to be true
    end

    it "handles empty event_ids array" do
      expect(persistence.mark_sent([])).to be true
    end
  end

  describe "#mark_sending" do
    it "marks events as sending" do
      event_id = persistence.persist({ type: "test" })
      persistence.flush

      result = persistence.mark_sending([event_id])

      expect(result).to be true
    end
  end

  describe "#mark_pending" do
    it "marks events as pending" do
      event_id = persistence.persist({ type: "test" })
      persistence.flush
      persistence.mark_sending([event_id])

      result = persistence.mark_pending([event_id])

      expect(result).to be true
    end
  end

  describe "#recover" do
    it "recovers pending events" do
      event_id = persistence.persist({ type: "test_recover", data: { key: "value" } })
      persistence.flush

      # Create a new persistence instance (simulating restart)
      persistence.close

      new_persistence = described_class.new(
        storage_path: storage_path,
        max_events: max_events,
        flush_interval: flush_interval,
        logger: logger
      )

      recovered = new_persistence.recover

      expect(recovered.size).to eq(1)
      expect(recovered.first[:id]).to eq(event_id)
      expect(recovered.first[:type]).to eq("test_recover")

      new_persistence.close
    end

    it "recovers events that were sending (crashed mid-send)" do
      event_id = persistence.persist({ type: "test_sending" })
      persistence.flush
      persistence.mark_sending([event_id])
      persistence.close

      new_persistence = described_class.new(
        storage_path: storage_path,
        max_events: max_events,
        flush_interval: flush_interval,
        logger: logger
      )

      recovered = new_persistence.recover

      expect(recovered.size).to eq(1)
      expect(recovered.first[:id]).to eq(event_id)

      new_persistence.close
    end

    it "does not recover sent events" do
      event_id = persistence.persist({ type: "test_sent" })
      persistence.flush
      persistence.mark_sent([event_id])
      persistence.close

      new_persistence = described_class.new(
        storage_path: storage_path,
        max_events: max_events,
        flush_interval: flush_interval,
        logger: logger
      )

      recovered = new_persistence.recover

      expect(recovered).to be_empty

      new_persistence.close
    end

    it "handles corrupted lines gracefully" do
      # Write valid event
      event_id = persistence.persist({ type: "valid_event" })
      persistence.flush

      # Append corrupted line to the file
      event_files = Dir.glob(File.join(storage_path, "flagkit-events-*.jsonl"))
      File.open(event_files.first, "a") do |f|
        f.puts("this is not valid json {{{")
      end

      persistence.close

      new_persistence = described_class.new(
        storage_path: storage_path,
        max_events: max_events,
        flush_interval: flush_interval,
        logger: logger
      )

      # Should still recover the valid event
      recovered = new_persistence.recover

      expect(recovered.size).to eq(1)
      expect(recovered.first[:id]).to eq(event_id)

      new_persistence.close
    end
  end

  describe "#cleanup" do
    it "removes old sent events" do
      event_id = persistence.persist({ type: "test_cleanup" })
      persistence.flush
      persistence.mark_sent([event_id])

      # Clean with 0 retention (immediate cleanup)
      cleaned = persistence.cleanup(retention_period: 0)

      expect(cleaned).to eq(1)
    end

    it "keeps recent sent events" do
      event_id = persistence.persist({ type: "test_keep" })
      persistence.flush
      persistence.mark_sent([event_id])

      # Clean with large retention period
      cleaned = persistence.cleanup(retention_period: 86_400)

      expect(cleaned).to eq(0)
    end

    it "keeps pending events" do
      persistence.persist({ type: "test_pending" })
      persistence.flush

      cleaned = persistence.cleanup(retention_period: 0)

      expect(cleaned).to eq(0)
    end
  end

  describe "#close" do
    it "flushes remaining events" do
      persistence.persist({ type: "final_event" })

      persistence.close

      event_files = Dir.glob(File.join(storage_path, "flagkit-events-*.jsonl"))
      expect(event_files).not_to be_empty

      content = File.read(event_files.first)
      expect(content).to include("final_event")
    end

    it "is idempotent" do
      persistence.close
      expect { persistence.close }.not_to raise_error
    end
  end

  describe "#pending_count" do
    it "counts buffered and persisted pending events" do
      persistence.persist({ type: "event1" })
      persistence.persist({ type: "event2" })
      persistence.flush
      persistence.persist({ type: "event3" }) # Still in buffer

      expect(persistence.pending_count).to eq(3)
    end
  end

  describe "file locking" do
    it "allows concurrent reads" do
      persistence.persist({ type: "test" })
      persistence.flush

      threads = 5.times.map do
        Thread.new { persistence.recover }
      end

      results = threads.map(&:value)

      expect(results.all? { |r| r.is_a?(Array) }).to be true
    end

    it "serializes writes" do
      threads = 10.times.map do |i|
        Thread.new do
          persistence.persist({ type: "event_#{i}", data: { index: i } })
        end
      end

      threads.each(&:join)
      persistence.flush

      # All events should be written
      expect(persistence.pending_count).to eq(10)
    end
  end

  describe "max_events limit" do
    let(:max_events) { 5 }

    it "drops oldest events when limit is exceeded" do
      # Persist more than max_events
      7.times do |i|
        persistence.persist({ type: "event_#{i}", timestamp: 1000 + i })
        persistence.flush
      end

      # Should only have max_events pending
      expect(persistence.pending_count).to be <= max_events
    end
  end

  describe "automatic flushing" do
    it "flushes events after flush interval" do
      persistence.persist({ type: "auto_flush_event" })

      # Wait for automatic flush (flush_interval is 100ms)
      sleep(0.15)

      event_files = Dir.glob(File.join(storage_path, "flagkit-events-*.jsonl"))
      expect(event_files).not_to be_empty

      content = File.read(event_files.first)
      expect(content).to include("auto_flush_event")
    end
  end

  describe "integration with EventQueue" do
    it "persists events through EventQueue" do
      flushed_events = []
      on_flush = ->(events) { flushed_events.concat(events) }

      queue = FlagKit::Core::EventQueue.new(
        batch_size: 10,
        flush_interval: 0.1,
        on_flush: on_flush,
        persist_events: true,
        event_storage_path: storage_path,
        max_persisted_events: 1000,
        persistence_flush_interval: 50
      )

      queue.enqueue({ type: "queued_event", data: { test: true } })
      queue.stop

      # Event should have been flushed
      expect(flushed_events.size).to eq(1)
      expect(flushed_events.first[:type]).to eq("queued_event")

      # Event should have an ID from persistence
      expect(flushed_events.first[:id]).to match(/^evt_[a-f0-9]{24}$/)
    end

    it "recovers events on queue start" do
      # First, persist some events directly
      event_id = persistence.persist({ type: "persisted_event", data: { recovered: true } })
      persistence.flush
      persistence.close

      # Now create an EventQueue that should recover the events
      flushed_events = []
      on_flush = ->(events) { flushed_events.concat(events) }

      queue = FlagKit::Core::EventQueue.new(
        batch_size: 10,
        flush_interval: 0.1,
        on_flush: on_flush,
        persist_events: true,
        event_storage_path: storage_path,
        max_persisted_events: 1000,
        persistence_flush_interval: 50
      )

      queue.start
      sleep(0.05) # Give time for recovery
      queue.stop

      # The recovered event should be in flushed events
      expect(flushed_events.any? { |e| e[:id] == event_id }).to be true
    end
  end
end
