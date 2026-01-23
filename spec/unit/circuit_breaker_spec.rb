# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::CircuitBreaker do
  let(:breaker) { described_class.new(failure_threshold: 3, reset_timeout: 0.2) }

  describe "#initialize" do
    it "starts in closed state" do
      expect(breaker.state).to eq(FlagKit::CircuitBreaker::State::CLOSED)
    end

    it "sets default values" do
      default_breaker = described_class.new
      expect(default_breaker.failure_threshold).to eq(5)
      expect(default_breaker.reset_timeout).to eq(30)
    end
  end

  describe "#allow_request?" do
    it "returns true when closed" do
      expect(breaker.allow_request?).to be true
    end

    it "returns false when open" do
      3.times { breaker.record_failure }
      expect(breaker.allow_request?).to be false
    end

    it "returns true when half-open" do
      3.times { breaker.record_failure }
      sleep(0.25)
      expect(breaker.allow_request?).to be true
    end
  end

  describe "#record_success" do
    it "resets failure count" do
      2.times { breaker.record_failure }
      breaker.record_success
      expect(breaker.failure_count).to eq(0)
    end

    it "transitions from half-open to closed" do
      3.times { breaker.record_failure }
      sleep(0.25)
      breaker.allow_request? # Triggers half-open
      breaker.record_success
      expect(breaker.closed?).to be true
    end
  end

  describe "#record_failure" do
    it "increments failure count" do
      breaker.record_failure
      expect(breaker.failure_count).to eq(1)
    end

    it "opens the circuit after threshold" do
      3.times { breaker.record_failure }
      expect(breaker.open?).to be true
    end
  end

  describe "#open?" do
    it "returns true when open" do
      3.times { breaker.record_failure }
      expect(breaker.open?).to be true
    end

    it "returns false when closed" do
      expect(breaker.open?).to be false
    end
  end

  describe "#closed?" do
    it "returns true when closed" do
      expect(breaker.closed?).to be true
    end

    it "returns false when open" do
      3.times { breaker.record_failure }
      expect(breaker.closed?).to be false
    end
  end

  describe "#half_open?" do
    it "returns true after reset timeout" do
      3.times { breaker.record_failure }
      sleep(0.25)
      expect(breaker.half_open?).to be true
    end
  end

  describe "#reset" do
    it "resets to closed state" do
      3.times { breaker.record_failure }
      breaker.reset
      expect(breaker.closed?).to be true
      expect(breaker.failure_count).to eq(0)
    end
  end

  describe "#call" do
    it "executes block and records success" do
      result = breaker.call { "success" }
      expect(result).to eq("success")
    end

    it "records failure on exception" do
      expect do
        breaker.call { raise "error" }
      end.to raise_error(RuntimeError, "error")
      expect(breaker.failure_count).to eq(1)
    end

    it "raises error when circuit is open" do
      3.times { breaker.record_failure }
      expect do
        breaker.call { "success" }
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CIRCUIT_OPEN)
      end
    end
  end

  describe "state transitions" do
    it "transitions CLOSED -> OPEN -> HALF_OPEN -> CLOSED" do
      # Start closed
      expect(breaker.closed?).to be true

      # Fail 3 times -> open
      3.times { breaker.record_failure }
      expect(breaker.open?).to be true

      # Wait for reset timeout -> half-open
      sleep(0.25)
      expect(breaker.half_open?).to be true

      # Success -> closed
      breaker.record_success
      expect(breaker.closed?).to be true
    end

    it "transitions HALF_OPEN -> OPEN on failure" do
      3.times { breaker.record_failure }
      sleep(0.25)
      expect(breaker.half_open?).to be true

      breaker.record_failure
      expect(breaker.open?).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do
        Thread.new do
          50.times do
            breaker.record_failure
            breaker.record_success
          end
        end
      end
      threads.each(&:join)
      # Just verify no errors occurred
    end
  end
end
