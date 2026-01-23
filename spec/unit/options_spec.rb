# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Options do
  let(:valid_api_key) { "sdk_test_key_123" }

  describe "#initialize" do
    it "sets default values" do
      options = described_class.new(api_key: valid_api_key)

      expect(options.api_key).to eq(valid_api_key)
      expect(options.polling_interval).to eq(30)
      expect(options.cache_ttl).to eq(300)
      expect(options.max_cache_size).to eq(1000)
      expect(options.cache_enabled).to be true
      expect(options.event_batch_size).to eq(10)
      expect(options.event_flush_interval).to eq(30)
      expect(options.events_enabled).to be true
      expect(options.timeout).to eq(10)
      expect(options.retry_attempts).to eq(3)
      expect(options.circuit_breaker_threshold).to eq(5)
      expect(options.circuit_breaker_reset_timeout).to eq(30)
    end

    it "accepts custom values" do
      options = described_class.new(
        api_key: valid_api_key,
        polling_interval: 60,
        cache_ttl: 600,
        cache_enabled: false
      )

      expect(options.polling_interval).to eq(60)
      expect(options.cache_ttl).to eq(600)
      expect(options.cache_enabled).to be false
    end
  end

  describe "#validate!" do
    it "raises error for missing API key" do
      expect do
        described_class.new(api_key: nil).validate!
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CONFIG_INVALID_API_KEY)
      end
    end

    it "raises error for empty API key" do
      expect do
        described_class.new(api_key: "").validate!
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CONFIG_INVALID_API_KEY)
      end
    end

    it "raises error for invalid API key prefix" do
      expect do
        described_class.new(api_key: "invalid_key").validate!
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CONFIG_INVALID_API_KEY)
        expect(error.message).to include("Invalid API key format")
      end
    end

    it "accepts valid API key prefixes" do
      %w[sdk_ srv_ cli_].each do |prefix|
        options = described_class.new(api_key: "#{prefix}test_key")
        expect { options.validate! }.not_to raise_error
      end
    end

    it "raises error for non-positive polling interval" do
      expect do
        described_class.new(api_key: valid_api_key, polling_interval: 0).validate!
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CONFIG_INVALID_POLLING_INTERVAL)
      end
    end

    it "raises error for non-positive cache TTL" do
      expect do
        described_class.new(api_key: valid_api_key, cache_ttl: -1).validate!
      end.to raise_error(FlagKit::Error) do |error|
        expect(error.code).to eq(FlagKit::ErrorCode::CONFIG_INVALID_CACHE_TTL)
      end
    end
  end
end
