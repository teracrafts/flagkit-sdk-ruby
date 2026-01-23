# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::EventQueue do
  let(:flushed_events) { [] }
  let(:on_flush) { ->(events) { flushed_events.concat(events) } }
  let(:queue) { described_class.new(batch_size: 3, flush_interval: 0.1, on_flush: on_flush) }

  after do
    queue.stop if queue.running?
  end

  describe "#initialize" do
    it "sets configuration values" do
      expect(queue.batch_size).to eq(3)
      expect(queue.flush_interval).to eq(0.1)
    end

    it "starts not running" do
      expect(queue.running?).to be false
    end
  end

  describe "#start and #stop" do
    it "starts the background flush thread" do
      queue.start
      expect(queue.running?).to be true
    end

    it "stops the background flush thread" do
      queue.start
      queue.stop
      expect(queue.running?).to be false
    end

    it "flushes remaining events on stop" do
      queue.enqueue({ type: "event1" })
      queue.stop

      expect(flushed_events.size).to eq(1)
    end
  end

  describe "#enqueue" do
    it "adds events to the queue" do
      queue.enqueue({ type: "event1" })
      expect(queue.size).to eq(1)
    end

    it "flushes when batch size is reached" do
      queue.enqueue({ type: "event1" })
      queue.enqueue({ type: "event2" })
      queue.enqueue({ type: "event3" })

      expect(flushed_events.size).to eq(3)
      expect(queue.size).to eq(0)
    end
  end

  describe "#flush" do
    it "sends all queued events" do
      queue.enqueue({ type: "event1" })
      queue.enqueue({ type: "event2" })
      queue.flush

      expect(flushed_events.size).to eq(2)
      expect(queue.size).to eq(0)
    end

    it "does nothing when queue is empty" do
      queue.flush
      expect(flushed_events).to be_empty
    end
  end

  describe "#size" do
    it "returns the number of pending events" do
      expect(queue.size).to eq(0)
      queue.enqueue({ type: "event1" })
      expect(queue.size).to eq(1)
    end
  end

  describe "automatic flushing" do
    it "flushes events after flush interval" do
      queue.start
      queue.enqueue({ type: "event1" })

      sleep(0.15)

      expect(flushed_events.size).to eq(1)
    end
  end

  describe "error handling" do
    it "re-queues events on flush failure" do
      error_count = 0
      failing_flush = lambda do |events|
        error_count += 1
        raise "Flush failed" if error_count == 1

        flushed_events.concat(events)
      end

      error_queue = described_class.new(batch_size: 10, flush_interval: 0.1, on_flush: failing_flush)

      error_queue.enqueue({ type: "event1" })
      error_queue.flush # First flush fails

      expect(error_queue.size).to eq(1) # Event re-queued

      error_queue.flush # Second flush succeeds
      expect(flushed_events.size).to eq(1)

      error_queue.stop
    end
  end
end
