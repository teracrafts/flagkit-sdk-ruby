# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Utils::Security do
  let(:security) { described_class }
  let(:test_api_key) { "sdk_test123456789abcdef" }

  # Reset configuration after each test
  after do
    security.reset_config!
  end

  describe ".potential_pii_field?" do
    context "with email fields" do
      it "detects 'email'" do
        expect(security.potential_pii_field?("email")).to be true
      end

      it "detects 'userEmail'" do
        expect(security.potential_pii_field?("userEmail")).to be true
      end

      it "detects 'EMAIL' (case-insensitive)" do
        expect(security.potential_pii_field?("EMAIL")).to be true
      end

      it "detects 'primary_email'" do
        expect(security.potential_pii_field?("primary_email")).to be true
      end
    end

    context "with phone fields" do
      it "detects 'phone'" do
        expect(security.potential_pii_field?("phone")).to be true
      end

      it "detects 'phoneNumber'" do
        expect(security.potential_pii_field?("phoneNumber")).to be true
      end

      it "detects 'mobile'" do
        expect(security.potential_pii_field?("mobile")).to be true
      end

      it "detects 'telephone'" do
        expect(security.potential_pii_field?("telephone")).to be true
      end
    end

    context "with SSN fields" do
      it "detects 'ssn'" do
        expect(security.potential_pii_field?("ssn")).to be true
      end

      it "detects 'socialSecurity'" do
        expect(security.potential_pii_field?("socialSecurity")).to be true
      end

      it "detects 'social_security'" do
        expect(security.potential_pii_field?("social_security")).to be true
      end
    end

    context "with credit card fields" do
      it "detects 'creditCard'" do
        expect(security.potential_pii_field?("creditCard")).to be true
      end

      it "detects 'credit_card'" do
        expect(security.potential_pii_field?("credit_card")).to be true
      end

      it "detects 'cardNumber'" do
        expect(security.potential_pii_field?("cardNumber")).to be true
      end

      it "detects 'cvv'" do
        expect(security.potential_pii_field?("cvv")).to be true
      end
    end

    context "with authentication fields" do
      it "detects 'password'" do
        expect(security.potential_pii_field?("password")).to be true
      end

      it "detects 'secret'" do
        expect(security.potential_pii_field?("secret")).to be true
      end

      it "detects 'apiKey'" do
        expect(security.potential_pii_field?("apiKey")).to be true
      end

      it "detects 'accessToken'" do
        expect(security.potential_pii_field?("accessToken")).to be true
      end

      it "detects 'refreshToken'" do
        expect(security.potential_pii_field?("refreshToken")).to be true
      end

      it "detects 'token'" do
        expect(security.potential_pii_field?("token")).to be true
      end
    end

    context "with address fields" do
      it "detects 'address'" do
        expect(security.potential_pii_field?("address")).to be true
      end

      it "detects 'street'" do
        expect(security.potential_pii_field?("street")).to be true
      end

      it "detects 'zipCode'" do
        expect(security.potential_pii_field?("zipCode")).to be true
      end

      it "detects 'postalCode'" do
        expect(security.potential_pii_field?("postalCode")).to be true
      end
    end

    context "with identity fields" do
      it "detects 'passport'" do
        expect(security.potential_pii_field?("passport")).to be true
      end

      it "detects 'driverLicense'" do
        expect(security.potential_pii_field?("driverLicense")).to be true
      end

      it "detects 'nationalId'" do
        expect(security.potential_pii_field?("nationalId")).to be true
      end

      it "detects 'dateOfBirth'" do
        expect(security.potential_pii_field?("dateOfBirth")).to be true
      end

      it "detects 'dob'" do
        expect(security.potential_pii_field?("dob")).to be true
      end
    end

    context "with banking fields" do
      it "detects 'bankAccount'" do
        expect(security.potential_pii_field?("bankAccount")).to be true
      end

      it "detects 'routingNumber'" do
        expect(security.potential_pii_field?("routingNumber")).to be true
      end

      it "detects 'iban'" do
        expect(security.potential_pii_field?("iban")).to be true
      end

      it "detects 'swift'" do
        expect(security.potential_pii_field?("swift")).to be true
      end
    end

    context "with safe fields" do
      it "does not flag 'userId'" do
        expect(security.potential_pii_field?("userId")).to be false
      end

      it "does not flag 'plan'" do
        expect(security.potential_pii_field?("plan")).to be false
      end

      it "does not flag 'country'" do
        expect(security.potential_pii_field?("country")).to be false
      end

      it "does not flag 'featureEnabled'" do
        expect(security.potential_pii_field?("featureEnabled")).to be false
      end

      it "does not flag 'name' by itself" do
        expect(security.potential_pii_field?("name")).to be false
      end
    end

    context "with edge cases" do
      it "handles nil" do
        expect(security.potential_pii_field?(nil)).to be false
      end

      it "handles symbols" do
        expect(security.potential_pii_field?(:email)).to be true
      end

      it "handles empty string" do
        expect(security.potential_pii_field?("")).to be false
      end
    end

    context "with custom PII patterns" do
      before do
        security.configure do |config|
          config.additional_pii_patterns = ["employee_id", "badge_number"]
        end
      end

      it "detects custom patterns" do
        expect(security.potential_pii_field?("employee_id")).to be true
        expect(security.potential_pii_field?("badge_number")).to be true
      end

      it "still detects default patterns" do
        expect(security.potential_pii_field?("email")).to be true
      end
    end
  end

  describe ".detect_potential_pii" do
    it "detects PII in flat objects" do
      data = {
        user_id: "user-123",
        email: "user@example.com",
        plan: "premium"
      }

      pii_fields = security.detect_potential_pii(data)

      expect(pii_fields).to include("email")
      expect(pii_fields).not_to include("user_id")
      expect(pii_fields).not_to include("plan")
    end

    it "detects PII in nested objects" do
      data = {
        user: {
          email: "user@example.com",
          phone: "123-456-7890"
        },
        settings: {
          dark_mode: true
        }
      }

      pii_fields = security.detect_potential_pii(data)

      expect(pii_fields).to include("user.email")
      expect(pii_fields).to include("user.phone")
      expect(pii_fields).not_to include("settings.dark_mode")
    end

    it "handles deeply nested objects" do
      data = {
        profile: {
          contact: {
            primary_email: "user@example.com"
          }
        }
      }

      pii_fields = security.detect_potential_pii(data)

      expect(pii_fields).to include("profile.contact.primary_email")
    end

    it "returns empty array for safe data" do
      data = {
        user_id: "user-123",
        plan: "premium",
        features: ["dark-mode", "beta"]
      }

      pii_fields = security.detect_potential_pii(data)

      expect(pii_fields).to be_empty
    end

    it "handles nil data" do
      expect(security.detect_potential_pii(nil)).to eq([])
    end

    it "handles non-hash data" do
      expect(security.detect_potential_pii("string")).to eq([])
      expect(security.detect_potential_pii(123)).to eq([])
      expect(security.detect_potential_pii([])).to eq([])
    end

    it "handles symbol keys" do
      data = { email: "test@example.com" }

      pii_fields = security.detect_potential_pii(data)

      expect(pii_fields).to include("email")
    end

    it "uses the prefix parameter" do
      data = { email: "test@example.com" }

      pii_fields = security.detect_potential_pii(data, "root")

      expect(pii_fields).to include("root.email")
    end
  end

  describe ".warn_if_potential_pii" do
    let(:mock_logger) { double("logger", warn: nil) }

    before do
      security.configure do |config|
        config.warn_on_potential_pii = true
      end
    end

    it "logs warning when PII is detected in context" do
      data = {
        email: "user@example.com",
        phone: "123-456-7890"
      }

      security.warn_if_potential_pii(data, :context, mock_logger)

      expect(mock_logger).to have_received(:warn).with(
        a_string_matching(/Potential PII detected/)
      )
      expect(mock_logger).to have_received(:warn).with(
        a_string_matching(/email/)
      )
      expect(mock_logger).to have_received(:warn).with(
        a_string_matching(/privateAttributes/)
      )
    end

    it "logs warning when PII is detected in event" do
      data = { password: "secret123" }

      security.warn_if_potential_pii(data, :event, mock_logger)

      expect(mock_logger).to have_received(:warn).with(
        a_string_matching(/removing sensitive data from events/)
      )
    end

    it "does not log when no PII is detected" do
      data = {
        user_id: "user-123",
        plan: "premium"
      }

      security.warn_if_potential_pii(data, :context, mock_logger)

      expect(mock_logger).not_to have_received(:warn)
    end

    it "handles nil data" do
      security.warn_if_potential_pii(nil, :event, mock_logger)

      expect(mock_logger).not_to have_received(:warn)
    end

    it "handles nil logger" do
      data = { email: "test@example.com" }

      # Should not raise
      expect { security.warn_if_potential_pii(data, :event, nil) }.not_to raise_error
    end

    it "respects warn_on_potential_pii config" do
      security.configure do |config|
        config.warn_on_potential_pii = false
      end

      data = { email: "test@example.com" }
      security.warn_if_potential_pii(data, :context, mock_logger)

      expect(mock_logger).not_to have_received(:warn)
    end

    it "handles logger without warn method" do
      basic_logger = Object.new

      data = { email: "test@example.com" }

      # Should not raise
      expect { security.warn_if_potential_pii(data, :event, basic_logger) }.not_to raise_error
    end

    context "with strict_pii_mode" do
      it "raises SecurityError when PII detected without private_attributes" do
        data = { email: "test@example.com" }

        error = nil
        begin
          security.warn_if_potential_pii(data, :context, mock_logger, strict_mode: true, has_private_attributes: false)
        rescue FlagKit::SecurityError => e
          error = e
        end
        expect(error).not_to be_nil
        expect(error.message).to include("Potential PII detected")
      end

      it "does not raise when has_private_attributes is true" do
        data = { email: "test@example.com" }

        expect {
          security.warn_if_potential_pii(data, :context, mock_logger, strict_mode: true, has_private_attributes: true)
        }.not_to raise_error
      end

      it "does not raise when no PII is detected" do
        data = { user_id: "user-123" }

        expect {
          security.warn_if_potential_pii(data, :context, mock_logger, strict_mode: true, has_private_attributes: false)
        }.not_to raise_error
      end
    end
  end

  describe ".server_key?" do
    it "returns true for server keys" do
      expect(security.server_key?("srv_abc123")).to be true
      expect(security.server_key?("srv_")).to be true
    end

    it "returns false for SDK keys" do
      expect(security.server_key?("sdk_abc123")).to be false
    end

    it "returns false for client keys" do
      expect(security.server_key?("cli_abc123")).to be false
    end

    it "returns false for invalid keys" do
      expect(security.server_key?("invalid_key")).to be false
    end

    it "handles nil" do
      expect(security.server_key?(nil)).to be false
    end

    it "handles symbols" do
      expect(security.server_key?(:srv_abc123)).to be true
    end
  end

  describe ".client_key?" do
    it "returns true for SDK keys" do
      expect(security.client_key?("sdk_abc123")).to be true
    end

    it "returns true for CLI keys" do
      expect(security.client_key?("cli_abc123")).to be true
    end

    it "returns false for server keys" do
      expect(security.client_key?("srv_abc123")).to be false
    end

    it "returns false for invalid keys" do
      expect(security.client_key?("invalid_key")).to be false
    end

    it "handles nil" do
      expect(security.client_key?(nil)).to be false
    end

    it "handles symbols" do
      expect(security.client_key?(:sdk_abc123)).to be true
    end
  end

  describe ".warn_if_server_key_in_browser" do
    let(:mock_logger) { double("logger", warn: nil) }

    before do
      security.configure do |config|
        config.warn_on_server_key_in_browser = true
      end
    end

    context "in browser-like environment (Opal)" do
      before do
        stub_const("RUBY_ENGINE", "opal")
      end

      it "warns when server key is used" do
        expect { security.warn_if_server_key_in_browser("srv_abc123", mock_logger) }
          .to output(/Server keys/).to_stderr

        expect(mock_logger).to have_received(:warn).with(
          a_string_matching(/Server keys \(srv_\) should not be used in browser/)
        )
      end

      it "does not warn for SDK keys" do
        expect { security.warn_if_server_key_in_browser("sdk_abc123", mock_logger) }
          .not_to output.to_stderr

        expect(mock_logger).not_to have_received(:warn)
      end

      it "does not warn for CLI keys" do
        expect { security.warn_if_server_key_in_browser("cli_abc123", mock_logger) }
          .not_to output.to_stderr

        expect(mock_logger).not_to have_received(:warn)
      end
    end

    context "with FLAGKIT_BROWSER_CONTEXT environment variable" do
      around do |example|
        original_value = ENV["FLAGKIT_BROWSER_CONTEXT"]
        ENV["FLAGKIT_BROWSER_CONTEXT"] = "true"
        example.run
        ENV["FLAGKIT_BROWSER_CONTEXT"] = original_value
      end

      it "warns when server key is used" do
        expect { security.warn_if_server_key_in_browser("srv_abc123", mock_logger) }
          .to output(/Server keys/).to_stderr
      end
    end

    context "in non-browser environment" do
      before do
        # Ensure we're not in a browser-like environment
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("FLAGKIT_BROWSER_CONTEXT").and_return(nil)
      end

      it "does not warn for server keys" do
        expect { security.warn_if_server_key_in_browser("srv_abc123", mock_logger) }
          .not_to output.to_stderr

        expect(mock_logger).not_to have_received(:warn)
      end
    end

    context "when warn_on_server_key_in_browser is disabled" do
      before do
        security.configure do |config|
          config.warn_on_server_key_in_browser = false
        end
        stub_const("RUBY_ENGINE", "opal")
      end

      it "does not warn even in browser environment" do
        expect { security.warn_if_server_key_in_browser("srv_abc123", mock_logger) }
          .not_to output.to_stderr

        expect(mock_logger).not_to have_received(:warn)
      end
    end

    it "handles nil logger" do
      stub_const("RUBY_ENGINE", "opal")

      expect { security.warn_if_server_key_in_browser("srv_abc123", nil) }
        .to output(/Server keys/).to_stderr
    end
  end

  describe ".config" do
    it "returns a SecurityConfig instance" do
      expect(security.config).to be_a(FlagKit::Utils::SecurityConfig)
    end

    it "returns the same instance on subsequent calls" do
      config1 = security.config
      config2 = security.config

      expect(config1).to be(config2)
    end
  end

  describe ".configure" do
    it "yields the config object" do
      expect { |b| security.configure(&b) }.to yield_with_args(FlagKit::Utils::SecurityConfig)
    end

    it "allows modifying configuration" do
      security.configure do |config|
        config.warn_on_potential_pii = false
        config.additional_pii_patterns = ["custom_field"]
      end

      expect(security.config.warn_on_potential_pii).to be false
      expect(security.config.additional_pii_patterns).to eq(["custom_field"])
    end

    it "returns the config object" do
      result = security.configure { |c| c.warn_on_potential_pii = true }

      expect(result).to be(security.config)
    end
  end

  describe ".reset_config!" do
    it "resets configuration to defaults" do
      security.configure do |config|
        config.warn_on_potential_pii = false
        config.additional_pii_patterns = ["custom"]
      end

      security.reset_config!

      expect(security.config.additional_pii_patterns).to eq([])
      expect(security.config.warn_on_server_key_in_browser).to be true
    end

    it "returns a new config instance" do
      old_config = security.config
      new_config = security.reset_config!

      expect(new_config).not_to be(old_config)
    end
  end
end

RSpec.describe FlagKit::Utils::SecurityConfig do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new

      expect(config.warn_on_server_key_in_browser).to be true
      expect(config.additional_pii_patterns).to eq([])
    end

    it "defaults warn_on_potential_pii based on environment" do
      config = described_class.new

      # In test environment, should default to true (non-production)
      expect(config.warn_on_potential_pii).to be true
    end

    it "accepts custom values" do
      config = described_class.new(
        warn_on_potential_pii: false,
        warn_on_server_key_in_browser: false,
        additional_pii_patterns: ["custom"]
      )

      expect(config.warn_on_potential_pii).to be false
      expect(config.warn_on_server_key_in_browser).to be false
      expect(config.additional_pii_patterns).to eq(["custom"])
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      config = described_class.new(
        warn_on_potential_pii: true,
        warn_on_server_key_in_browser: false,
        additional_pii_patterns: ["test"]
      )

      hash = config.to_h

      expect(hash).to eq(
        warn_on_potential_pii: true,
        warn_on_server_key_in_browser: false,
        additional_pii_patterns: ["test"]
      )
    end
  end

  describe "accessors" do
    it "allows reading and writing warn_on_potential_pii" do
      config = described_class.new
      config.warn_on_potential_pii = false

      expect(config.warn_on_potential_pii).to be false
    end

    it "allows reading and writing warn_on_server_key_in_browser" do
      config = described_class.new
      config.warn_on_server_key_in_browser = false

      expect(config.warn_on_server_key_in_browser).to be false
    end

    it "allows reading and writing additional_pii_patterns" do
      config = described_class.new
      config.additional_pii_patterns = ["field1", "field2"]

      expect(config.additional_pii_patterns).to eq(["field1", "field2"])
    end
  end

  describe "environment-based defaults" do
    around do |example|
      original_env = ENV["RUBY_ENV"]
      example.run
      ENV["RUBY_ENV"] = original_env
    end

    it "sets warn_on_potential_pii to false in production" do
      ENV["RUBY_ENV"] = "production"

      config = described_class.new

      expect(config.warn_on_potential_pii).to be false
    end

    it "sets warn_on_potential_pii to true in development" do
      ENV["RUBY_ENV"] = "development"

      config = described_class.new

      expect(config.warn_on_potential_pii).to be true
    end

    it "sets warn_on_potential_pii to true in test" do
      ENV["RUBY_ENV"] = "test"

      config = described_class.new

      expect(config.warn_on_potential_pii).to be true
    end
  end
end

RSpec.describe FlagKit::Utils::Security, "HMAC-SHA256 Request Signing" do
  let(:security) { described_class }
  let(:test_api_key) { "sdk_test123456789abcdef" }

  describe ".get_key_id" do
    it "returns first 8 characters of API key" do
      expect(security.get_key_id(test_api_key)).to eq("sdk_test")
    end

    it "handles short keys" do
      expect(security.get_key_id("sdk")).to eq("sdk")
    end

    it "handles nil" do
      expect(security.get_key_id(nil)).to eq("")
    end
  end

  describe ".generate_hmac_sha256" do
    it "generates consistent signatures for same input" do
      sig1 = security.generate_hmac_sha256("message", "key")
      sig2 = security.generate_hmac_sha256("message", "key")

      expect(sig1).to eq(sig2)
    end

    it "generates different signatures for different messages" do
      sig1 = security.generate_hmac_sha256("message1", "key")
      sig2 = security.generate_hmac_sha256("message2", "key")

      expect(sig1).not_to eq(sig2)
    end

    it "generates different signatures for different keys" do
      sig1 = security.generate_hmac_sha256("message", "key1")
      sig2 = security.generate_hmac_sha256("message", "key2")

      expect(sig1).not_to eq(sig2)
    end

    it "returns a 64-character hex string" do
      sig = security.generate_hmac_sha256("message", "key")

      expect(sig).to match(/^[a-f0-9]{64}$/)
    end
  end

  describe ".create_request_signature" do
    it "returns signature, timestamp, and key_id" do
      result = security.create_request_signature('{"key":"value"}', test_api_key)

      expect(result).to have_key(:signature)
      expect(result).to have_key(:timestamp)
      expect(result).to have_key(:key_id)
    end

    it "uses provided timestamp" do
      timestamp = 1234567890000
      result = security.create_request_signature('{"key":"value"}', test_api_key, timestamp: timestamp)

      expect(result[:timestamp]).to eq(timestamp)
    end

    it "generates current timestamp if not provided" do
      before_time = (Time.now.to_f * 1000).to_i
      result = security.create_request_signature('{"key":"value"}', test_api_key)
      after_time = (Time.now.to_f * 1000).to_i

      expect(result[:timestamp]).to be >= before_time
      expect(result[:timestamp]).to be <= after_time
    end

    it "includes correct key_id" do
      result = security.create_request_signature('{"key":"value"}', test_api_key)

      expect(result[:key_id]).to eq("sdk_test")
    end
  end

  describe ".sign_payload" do
    it "signs a payload with data, signature, timestamp, and key_id" do
      data = { events: [{ type: "test" }] }
      result = security.sign_payload(data, test_api_key)

      expect(result[:data]).to eq(data)
      expect(result[:signature]).to be_a(String)
      expect(result[:timestamp]).to be_a(Integer)
      expect(result[:key_id]).to eq("sdk_test")
    end

    it "uses provided timestamp" do
      timestamp = 1234567890000
      result = security.sign_payload({ test: true }, test_api_key, timestamp: timestamp)

      expect(result[:timestamp]).to eq(timestamp)
    end
  end

  describe ".verify_signed_payload" do
    it "verifies a valid signed payload" do
      data = { events: [{ type: "test" }] }
      signed = security.sign_payload(data, test_api_key)

      expect(security.verify_signed_payload(signed, test_api_key)).to be true
    end

    it "rejects payload with wrong signature" do
      signed = {
        data: { test: true },
        signature: "wrong_signature",
        timestamp: (Time.now.to_f * 1000).to_i,
        key_id: "sdk_test"
      }

      expect(security.verify_signed_payload(signed, test_api_key)).to be false
    end

    it "rejects payload with wrong key_id" do
      data = { test: true }
      signed = security.sign_payload(data, test_api_key)
      signed[:key_id] = "wrong_id"

      expect(security.verify_signed_payload(signed, test_api_key)).to be false
    end

    it "rejects expired payload" do
      data = { test: true }
      old_timestamp = (Time.now.to_f * 1000).to_i - 400_000 # 400 seconds ago
      signed = security.sign_payload(data, test_api_key, timestamp: old_timestamp)

      expect(security.verify_signed_payload(signed, test_api_key, max_age_ms: 300_000)).to be false
    end

    it "rejects payload with future timestamp" do
      data = { test: true }
      future_timestamp = (Time.now.to_f * 1000).to_i + 100_000
      signed = security.sign_payload(data, test_api_key, timestamp: future_timestamp)

      expect(security.verify_signed_payload(signed, test_api_key)).to be false
    end
  end
end

RSpec.describe FlagKit::Options, "Security Options" do
  describe "security options" do
    it "supports secondary_api_key option" do
      options = FlagKit::Options.new(
        api_key: "sdk_primary",
        secondary_api_key: "sdk_secondary"
      )

      expect(options.secondary_api_key).to eq("sdk_secondary")
    end

    it "supports key_rotation_grace_period option" do
      options = FlagKit::Options.new(
        api_key: "sdk_test123",
        key_rotation_grace_period: 600
      )

      expect(options.key_rotation_grace_period).to eq(600)
    end

    it "defaults key_rotation_grace_period to 300 seconds" do
      options = FlagKit::Options.new(api_key: "sdk_test123")

      expect(options.key_rotation_grace_period).to eq(300)
    end

    it "supports strict_pii_mode option" do
      options = FlagKit::Options.new(
        api_key: "sdk_test123",
        strict_pii_mode: true
      )

      expect(options.strict_pii_mode).to be true
    end

    it "defaults strict_pii_mode to false" do
      options = FlagKit::Options.new(api_key: "sdk_test123")

      expect(options.strict_pii_mode).to be false
    end

    it "supports enable_request_signing option" do
      options = FlagKit::Options.new(
        api_key: "sdk_test123",
        enable_request_signing: false
      )

      expect(options.enable_request_signing).to be false
    end

    it "defaults enable_request_signing to true" do
      options = FlagKit::Options.new(api_key: "sdk_test123")

      expect(options.enable_request_signing).to be true
    end

    it "supports encrypt_cache option" do
      options = FlagKit::Options.new(
        api_key: "sdk_test123",
        encrypt_cache: true
      )

      expect(options.encrypt_cache).to be true
    end

    it "defaults encrypt_cache to false" do
      options = FlagKit::Options.new(api_key: "sdk_test123")

      expect(options.encrypt_cache).to be false
    end
  end
end

RSpec.describe FlagKit::Core::EncryptedCache do
  let(:api_key) { "sdk_test123456789abcdef" }
  let(:cache) { described_class.new(api_key: api_key, ttl: 300) }

  describe "#initialize" do
    it "creates an encrypted cache" do
      expect(cache).to be_a(FlagKit::Core::EncryptedCache)
    end

    it "reports encryption as available" do
      expect(cache.encryption_available?).to be true
    end
  end

  describe "#set and #get" do
    it "stores and retrieves simple values" do
      cache.set("key1", "value1")

      expect(cache.get("key1")).to eq("value1")
    end

    it "stores and retrieves hashes" do
      data = { "name" => "test", "enabled" => true }
      cache.set("hash_key", data)

      expect(cache.get("hash_key")).to eq(data)
    end

    it "stores and retrieves arrays" do
      data = [1, 2, 3, "four"]
      cache.set("array_key", data)

      expect(cache.get("array_key")).to eq(data)
    end

    it "stores and retrieves nested structures" do
      data = {
        "user" => { "id" => 123, "name" => "test" },
        "flags" => [{ "key" => "feature1", "enabled" => true }]
      }
      cache.set("nested_key", data)

      expect(cache.get("nested_key")).to eq(data)
    end

    it "returns nil for non-existent keys" do
      expect(cache.get("nonexistent")).to be_nil
    end
  end

  describe "encryption verification" do
    it "actually encrypts data (raw cache contains encrypted data)" do
      cache.set("test_key", "secret_value")

      # Access the internal cache to verify encryption
      raw_value = cache.instance_variable_get(:@cache).get("test_key")

      # Raw value should be JSON with encryption fields
      parsed = JSON.parse(raw_value)
      expect(parsed).to have_key("iv")
      expect(parsed).to have_key("data")
      expect(parsed).to have_key("tag")
      expect(parsed).to have_key("version")

      # The encrypted data should not contain the plaintext
      expect(raw_value).not_to include("secret_value")
    end

    it "uses different IVs for each encryption" do
      cache.set("key1", "same_value")
      cache.set("key2", "same_value")

      raw1 = cache.instance_variable_get(:@cache).get("key1")
      raw2 = cache.instance_variable_get(:@cache).get("key2")

      parsed1 = JSON.parse(raw1)
      parsed2 = JSON.parse(raw2)

      # IVs should be different
      expect(parsed1["iv"]).not_to eq(parsed2["iv"])
      # Ciphertext should also be different due to different IVs
      expect(parsed1["data"]).not_to eq(parsed2["data"])
    end
  end

  describe "#has?" do
    it "returns true for existing keys" do
      cache.set("existing", "value")

      expect(cache.has?("existing")).to be true
    end

    it "returns false for non-existent keys" do
      expect(cache.has?("nonexistent")).to be false
    end
  end

  describe "#delete" do
    it "removes a key from the cache" do
      cache.set("to_delete", "value")
      cache.delete("to_delete")

      expect(cache.has?("to_delete")).to be false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear

      expect(cache.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns the number of entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      expect(cache.size).to eq(2)
    end
  end

  describe "#keys" do
    it "returns all keys" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      expect(cache.keys).to contain_exactly("key1", "key2")
    end
  end

  describe "#to_h" do
    it "returns all decrypted values" do
      cache.set("key1", "value1")
      cache.set("key2", { "nested" => true })

      result = cache.to_h

      expect(result["key1"]).to eq("value1")
      expect(result["key2"]).to eq({ "nested" => true })
    end
  end

  describe "#set_all" do
    it "sets multiple values" do
      cache.set_all(
        "key1" => "value1",
        "key2" => "value2"
      )

      expect(cache.get("key1")).to eq("value1")
      expect(cache.get("key2")).to eq("value2")
    end
  end

  describe "different API keys produce different encryption" do
    it "cannot decrypt data encrypted with different key" do
      cache1 = described_class.new(api_key: "sdk_key1_abcdef123456")
      cache2 = described_class.new(api_key: "sdk_key2_xyz789012345")

      cache1.set("shared_key", "secret_data")

      # Copy encrypted data to cache2's internal cache
      raw_encrypted = cache1.instance_variable_get(:@cache).get("shared_key")
      cache2.instance_variable_get(:@cache).set("shared_key", raw_encrypted)

      # cache2 should fail to decrypt (returns nil due to auth tag mismatch)
      expect(cache2.get("shared_key")).to be_nil
    end
  end
end
