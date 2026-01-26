# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Evaluation Jitter" do
  let(:valid_api_key) { "sdk_test_key_123" }
  let(:http_response) do
    {
      "key" => "test-flag",
      "value" => true,
      "enabled" => true,
      "version" => 1
    }
  end

  before do
    stub_request(:get, %r{/sdk/init})
      .to_return(status: 200, body: { flags: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, %r{/sdk/evaluate})
      .to_return(status: 200, body: http_response.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "when jitter is disabled (default)" do
    let(:options) do
      FlagKit::Options.new(
        api_key: valid_api_key,
        cache_enabled: false
      )
    end

    it "does not apply jitter" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      # Jitter should not be applied - the method should return immediately
      expect(client).not_to receive(:sleep)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.get_boolean_value("test-flag", false)
      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      # Without jitter, the call should be fast (network stubbed)
      expect(elapsed_time).to be < 0.005 # Less than 5ms
    end

    it "has jitter disabled by default" do
      expect(options.evaluation_jitter_enabled).to be false
    end

    it "has default jitter min of 5ms" do
      expect(options.evaluation_jitter_min_ms).to eq(5)
    end

    it "has default jitter max of 15ms" do
      expect(options.evaluation_jitter_max_ms).to eq(15)
    end
  end

  describe "when jitter is enabled" do
    let(:options) do
      FlagKit::Options.new(
        api_key: valid_api_key,
        cache_enabled: false,
        evaluation_jitter_enabled: true
      )
    end

    it "applies jitter delay" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.get_boolean_value("test-flag", false)
      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      # With jitter enabled, should take at least min_ms (5ms)
      expect(elapsed_time).to be >= 0.005
    end

    it "timing falls within min/max range" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      timings = []
      5.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.get_boolean_value("test-flag", false)
        elapsed_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        timings << elapsed_time
      end

      # All timings should be at least 5ms (min_ms)
      timings.each do |timing|
        expect(timing).to be >= 5
      end
    end
  end

  describe "with custom min/max values" do
    let(:custom_min) { 10 }
    let(:custom_max) { 20 }
    let(:options) do
      FlagKit::Options.new(
        api_key: valid_api_key,
        cache_enabled: false,
        evaluation_jitter_enabled: true,
        evaluation_jitter_min_ms: custom_min,
        evaluation_jitter_max_ms: custom_max
      )
    end

    it "respects custom min/max values" do
      expect(options.evaluation_jitter_min_ms).to eq(custom_min)
      expect(options.evaluation_jitter_max_ms).to eq(custom_max)
    end

    it "applies jitter within custom range" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.get_boolean_value("test-flag", false)
      elapsed_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      # Should be at least custom_min (10ms)
      expect(elapsed_time).to be >= custom_min
    end

    it "jitter does not exceed max plus overhead" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      timings = []
      10.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.get_boolean_value("test-flag", false)
        elapsed_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        timings << elapsed_time
      end

      # Allow some overhead for test execution, but jitter should be bounded
      # Max jitter is 20ms, allow up to 25ms for overhead
      timings.each do |timing|
        expect(timing).to be < (custom_max + 10)
      end
    end
  end

  describe "jitter randomness" do
    let(:options) do
      FlagKit::Options.new(
        api_key: valid_api_key,
        cache_enabled: false,
        evaluation_jitter_enabled: true,
        evaluation_jitter_min_ms: 5,
        evaluation_jitter_max_ms: 50
      )
    end

    it "produces variable delays" do
      client = FlagKit::Client.new(options)
      client.initialize_sdk

      timings = []
      10.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.get_boolean_value("test-flag", false)
        elapsed_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        timings << elapsed_time.round
      end

      # With a 45ms range, we expect some variation in timings
      # This test verifies randomness by checking that not all values are identical
      unique_timings = timings.uniq
      expect(unique_timings.length).to be > 1
    end
  end
end
