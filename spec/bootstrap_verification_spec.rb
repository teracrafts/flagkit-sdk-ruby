# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Utils::Security, "Bootstrap Verification" do
  let(:security) { described_class }
  let(:test_api_key) { "sdk_test123456789abcdef" }

  after do
    security.reset_config!
  end

  describe ".canonicalize_object" do
    it "sorts keys alphabetically" do
      obj = { z: 1, a: 2, m: 3 }
      result = security.canonicalize_object(obj)

      expect(result).to eq('{"a":2,"m":3,"z":1}')
    end

    it "sorts nested object keys" do
      obj = { outer: { z: 1, a: 2 }, first: true }
      result = security.canonicalize_object(obj)

      expect(result).to eq('{"first":true,"outer":{"a":2,"z":1}}')
    end

    it "handles arrays without reordering" do
      obj = { items: [3, 1, 2] }
      result = security.canonicalize_object(obj)

      expect(result).to eq('{"items":[3,1,2]}')
    end

    it "sorts keys in objects within arrays" do
      obj = { items: [{ z: 1, a: 2 }] }
      result = security.canonicalize_object(obj)

      expect(result).to eq('{"items":[{"a":2,"z":1}]}')
    end

    it "handles string keys" do
      obj = { "zebra" => 1, "apple" => 2 }
      result = security.canonicalize_object(obj)

      expect(result).to eq('{"apple":2,"zebra":1}')
    end

    it "handles mixed key types" do
      obj = { "string_key" => 1, symbol_key: 2 }
      result = security.canonicalize_object(obj)

      # Keys sorted by string representation
      expect(JSON.parse(result).keys).to eq(["string_key", "symbol_key"])
    end
  end

  describe ".verify_bootstrap_signature" do
    let(:flags) { { "feature_one" => true, "feature_two" => false } }
    let(:timestamp) { (Time.now.to_f * 1000).to_i }

    def create_valid_bootstrap(flags, api_key, ts = nil)
      ts ||= (Time.now.to_f * 1000).to_i
      canonical_flags = security.canonicalize_object(flags)
      message = "#{ts}.#{canonical_flags}"
      signature = security.generate_hmac_sha256(message, api_key)

      {
        flags: flags,
        signature: signature,
        timestamp: ts
      }
    end

    context "with valid signature" do
      it "returns valid: true" do
        bootstrap = create_valid_bootstrap(flags, test_api_key)
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be true
        expect(result[:error]).to be_nil
      end

      it "accepts string keys in bootstrap" do
        bootstrap = create_valid_bootstrap(flags, test_api_key)
        string_bootstrap = {
          "flags" => bootstrap[:flags],
          "signature" => bootstrap[:signature],
          "timestamp" => bootstrap[:timestamp]
        }
        result = security.verify_bootstrap_signature(string_bootstrap, test_api_key)

        expect(result[:valid]).to be true
      end

      it "handles complex nested flags" do
        complex_flags = {
          "feature" => {
            "enabled" => true,
            "config" => { "threshold" => 0.5, "active" => true }
          },
          "another_feature" => false
        }
        bootstrap = create_valid_bootstrap(complex_flags, test_api_key)
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be true
      end
    end

    context "with invalid signature" do
      it "returns valid: false with error message" do
        bootstrap = {
          flags: flags,
          signature: "invalid_signature",
          timestamp: timestamp
        }
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Invalid signature")
      end

      it "rejects signature signed with different key" do
        bootstrap = create_valid_bootstrap(flags, "sdk_different_key_12345")
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Invalid signature")
      end

      it "rejects tampered flags" do
        bootstrap = create_valid_bootstrap(flags, test_api_key)
        bootstrap[:flags]["feature_one"] = false # Tamper with the data
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Invalid signature")
      end
    end

    context "with expired timestamp" do
      it "returns valid: false when timestamp is too old" do
        old_timestamp = (Time.now.to_f * 1000).to_i - 100_000_000 # ~27 hours ago
        bootstrap = create_valid_bootstrap(flags, test_api_key, old_timestamp)
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to match(/Bootstrap data expired/)
      end

      it "respects custom max_age_ms" do
        one_hour_ago = (Time.now.to_f * 1000).to_i - 3_600_000
        bootstrap = create_valid_bootstrap(flags, test_api_key, one_hour_ago)

        # Should fail with 30 minute max age
        result = security.verify_bootstrap_signature(bootstrap, test_api_key, max_age_ms: 1_800_000)
        expect(result[:valid]).to be false

        # Should pass with 2 hour max age
        result = security.verify_bootstrap_signature(bootstrap, test_api_key, max_age_ms: 7_200_000)
        expect(result[:valid]).to be true
      end
    end

    context "with future timestamp" do
      it "returns valid: false" do
        future_timestamp = (Time.now.to_f * 1000).to_i + 100_000
        bootstrap = create_valid_bootstrap(flags, test_api_key, future_timestamp)
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Bootstrap timestamp is in the future")
      end
    end

    context "with missing fields" do
      it "returns error when signature is missing" do
        bootstrap = { flags: flags, timestamp: timestamp }
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Missing signature")
      end

      it "returns error when timestamp is missing" do
        bootstrap = { flags: flags, signature: "some_signature" }
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Missing timestamp")
      end

      it "returns error when flags is missing" do
        bootstrap = { signature: "some_signature", timestamp: timestamp }
        result = security.verify_bootstrap_signature(bootstrap, test_api_key)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Missing flags")
      end
    end
  end
end

RSpec.describe FlagKit::Options, "Bootstrap Verification Options" do
  describe "default values" do
    let(:options) { described_class.new(api_key: "sdk_test123") }

    it "defaults bootstrap_verification_enabled to true" do
      expect(options.bootstrap_verification_enabled).to be true
    end

    it "defaults bootstrap_verification_max_age to 24 hours in milliseconds" do
      expect(options.bootstrap_verification_max_age).to eq(86_400_000)
    end

    it "defaults bootstrap_verification_on_failure to 'warn'" do
      expect(options.bootstrap_verification_on_failure).to eq("warn")
    end
  end

  describe "custom values" do
    it "accepts custom bootstrap_verification_enabled" do
      options = described_class.new(
        api_key: "sdk_test123",
        bootstrap_verification_enabled: false
      )

      expect(options.bootstrap_verification_enabled).to be false
    end

    it "accepts custom bootstrap_verification_max_age" do
      options = described_class.new(
        api_key: "sdk_test123",
        bootstrap_verification_max_age: 3_600_000
      )

      expect(options.bootstrap_verification_max_age).to eq(3_600_000)
    end

    it "accepts custom bootstrap_verification_on_failure" do
      options = described_class.new(
        api_key: "sdk_test123",
        bootstrap_verification_on_failure: "error"
      )

      expect(options.bootstrap_verification_on_failure).to eq("error")
    end
  end
end

RSpec.describe FlagKit::Client, "Bootstrap Verification" do
  let(:test_api_key) { "sdk_test123456789abcdef" }
  let(:security) { FlagKit::Utils::Security }
  let(:mock_logger) { double("logger", info: nil, warn: nil, error: nil, debug: nil) }

  def create_valid_bootstrap(flags, api_key, ts = nil)
    ts ||= (Time.now.to_f * 1000).to_i
    canonical_flags = security.canonicalize_object(flags)
    message = "#{ts}.#{canonical_flags}"
    signature = security.generate_hmac_sha256(message, api_key)

    {
      flags: flags,
      signature: signature,
      timestamp: ts
    }
  end

  def create_flag_data(key, value, enabled = true)
    {
      "key" => key,
      "value" => value,
      "enabled" => enabled,
      "version" => 1
    }
  end

  before do
    # Stub the HTTP calls
    stub_request(:get, /api\.flagkit\.dev.*init/)
      .to_return(status: 200, body: '{"flags":[]}', headers: { "Content-Type" => "application/json" })
  end

  describe "with valid signed bootstrap" do
    it "loads flags from signed bootstrap" do
      flag_data = [create_flag_data("my_feature", true)]
      bootstrap = create_valid_bootstrap(flag_data, test_api_key)

      options = FlagKit::Options.new(
        api_key: test_api_key,
        bootstrap: bootstrap,
        logger: mock_logger
      )

      client = FlagKit::Client.new(options)
      client.send(:load_bootstrap)

      # Flag should be in cache
      cached = client.send(:get_cached_flag, "my_feature")
      expect(cached).not_to be_nil
      expect(cached.value).to be true
    end
  end

  describe "with invalid signed bootstrap" do
    context "when on_failure is 'warn'" do
      it "logs warning and still loads flags" do
        flag_data = [create_flag_data("my_feature", true)]
        bootstrap = {
          flags: flag_data,
          signature: "invalid_signature",
          timestamp: (Time.now.to_f * 1000).to_i
        }

        options = FlagKit::Options.new(
          api_key: test_api_key,
          bootstrap: bootstrap,
          bootstrap_verification_on_failure: "warn",
          logger: mock_logger
        )

        client = FlagKit::Client.new(options)
        client.send(:load_bootstrap)

        expect(mock_logger).to have_received(:warn).with(/Bootstrap verification failed/)

        # Flag should still be in cache (warn mode continues)
        cached = client.send(:get_cached_flag, "my_feature")
        expect(cached).not_to be_nil
      end
    end

    context "when on_failure is 'error'" do
      it "raises an error and does not load flags" do
        flag_data = [create_flag_data("my_feature", true)]
        bootstrap = {
          flags: flag_data,
          signature: "invalid_signature",
          timestamp: (Time.now.to_f * 1000).to_i
        }

        options = FlagKit::Options.new(
          api_key: test_api_key,
          bootstrap: bootstrap,
          bootstrap_verification_on_failure: "error",
          logger: mock_logger
        )

        client = FlagKit::Client.new(options)

        expect { client.send(:load_bootstrap) }.to raise_error(
          FlagKit::Error,
          /Bootstrap verification failed/
        )
      end
    end

    context "when on_failure is 'ignore'" do
      it "silently continues and loads flags" do
        flag_data = [create_flag_data("my_feature", true)]
        bootstrap = {
          flags: flag_data,
          signature: "invalid_signature",
          timestamp: (Time.now.to_f * 1000).to_i
        }

        options = FlagKit::Options.new(
          api_key: test_api_key,
          bootstrap: bootstrap,
          bootstrap_verification_on_failure: "ignore",
          logger: mock_logger
        )

        client = FlagKit::Client.new(options)
        client.send(:load_bootstrap)

        expect(mock_logger).not_to have_received(:warn)

        # Flag should still be in cache
        cached = client.send(:get_cached_flag, "my_feature")
        expect(cached).not_to be_nil
      end
    end
  end

  describe "with expired bootstrap" do
    it "handles expired timestamp according to on_failure setting" do
      flag_data = [create_flag_data("my_feature", true)]
      old_timestamp = (Time.now.to_f * 1000).to_i - 100_000_000 # ~27 hours ago
      bootstrap = create_valid_bootstrap(flag_data, test_api_key, old_timestamp)

      options = FlagKit::Options.new(
        api_key: test_api_key,
        bootstrap: bootstrap,
        bootstrap_verification_on_failure: "warn",
        logger: mock_logger
      )

      client = FlagKit::Client.new(options)
      client.send(:load_bootstrap)

      expect(mock_logger).to have_received(:warn).with(/Bootstrap verification failed.*expired/)
    end
  end

  describe "with legacy bootstrap format" do
    it "loads flags from legacy array format without verification" do
      flag_data = [create_flag_data("legacy_feature", "enabled")]

      options = FlagKit::Options.new(
        api_key: test_api_key,
        bootstrap: { "flags" => flag_data }, # Legacy format: just flags, no signature
        logger: mock_logger
      )

      client = FlagKit::Client.new(options)
      client.send(:load_bootstrap)

      # Flag should be in cache
      cached = client.send(:get_cached_flag, "legacy_feature")
      expect(cached).not_to be_nil
      expect(cached.value).to eq("enabled")
    end
  end

  describe "with verification disabled" do
    it "skips verification even for signed bootstrap" do
      flag_data = [create_flag_data("my_feature", true)]
      bootstrap = {
        flags: flag_data,
        signature: "invalid_signature",
        timestamp: (Time.now.to_f * 1000).to_i
      }

      options = FlagKit::Options.new(
        api_key: test_api_key,
        bootstrap: bootstrap,
        bootstrap_verification_enabled: false,
        logger: mock_logger
      )

      client = FlagKit::Client.new(options)
      client.send(:load_bootstrap)

      # Should not warn because verification is disabled
      expect(mock_logger).not_to have_received(:warn)

      # Flag should be in cache
      cached = client.send(:get_cached_flag, "my_feature")
      expect(cached).not_to be_nil
    end
  end
end
