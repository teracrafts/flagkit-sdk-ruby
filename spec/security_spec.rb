# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Utils::Security do
  let(:security) { described_class }

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
