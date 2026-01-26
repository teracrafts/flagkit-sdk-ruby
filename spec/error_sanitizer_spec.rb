# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::ErrorSanitizer do
  describe ".sanitize" do
    context "when sanitization is enabled" do
      it "sanitizes Unix-style file paths" do
        message = "Failed to read /home/user/config/secrets.json"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Failed to read [PATH]")
      end

      it "sanitizes deeply nested Unix paths" do
        message = "Error at /var/log/app/flagkit/debug.log"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Error at [PATH]")
      end

      it "sanitizes Windows-style file paths" do
        message = "Cannot open C:\\Users\\Admin\\Documents\\config.yaml"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Cannot open [PATH]")
      end

      it "sanitizes Windows paths with lowercase drive letter" do
        message = "File not found: d:\\projects\\secret\\key.pem"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("File not found: [PATH]")
      end

      it "sanitizes IPv4 addresses" do
        message = "Connection refused to 192.168.1.100"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Connection refused to [IP]")
      end

      it "sanitizes multiple IP addresses" do
        message = "Proxy 10.0.0.1 forwarded to 172.16.0.50"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Proxy [IP] forwarded to [IP]")
      end

      it "sanitizes SDK API keys" do
        message = "Invalid key: sdk_abc123xyz789_test_key"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Invalid key: sdk_[REDACTED]")
      end

      it "sanitizes server API keys" do
        message = "Unauthorized: srv_secretkey12345678"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Unauthorized: srv_[REDACTED]")
      end

      it "sanitizes CLI API keys" do
        message = "Token cli_mytoken123456789 expired"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Token cli_[REDACTED] expired")
      end

      it "does not sanitize short API key prefixes" do
        # Keys with less than 8 characters after prefix should not match
        message = "Key sdk_short"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Key sdk_short")
      end

      it "sanitizes email addresses" do
        message = "User john.doe@example.com not found"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("User [EMAIL] not found")
      end

      it "sanitizes complex email addresses" do
        message = "Contact admin-user.name@sub.domain.org for support"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Contact [EMAIL] for support")
      end

      it "sanitizes PostgreSQL connection strings" do
        message = "Failed to connect: postgres://user:password@localhost:5432/mydb"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Failed to connect: [CONNECTION_STRING]")
      end

      it "sanitizes MySQL connection strings" do
        message = "Database error: mysql://root:secret@db.example.com/production"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Database error: [CONNECTION_STRING]")
      end

      it "sanitizes MongoDB connection strings" do
        message = "Timeout: mongodb://admin:pass123@cluster.mongodb.net/test"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Timeout: [CONNECTION_STRING]")
      end

      it "sanitizes Redis connection strings" do
        message = "Connection lost: redis://default:auth@redis.server.io:6379"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Connection lost: [CONNECTION_STRING]")
      end

      it "sanitizes connection strings case-insensitively" do
        message = "Error: POSTGRES://user:pass@host/db"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Error: [CONNECTION_STRING]")
      end

      it "sanitizes multiple patterns in one message" do
        message = "User admin@corp.com at 192.168.1.1 used sdk_apikey12345678 to access /etc/passwd"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("User [EMAIL] at [IP] used sdk_[REDACTED] to access [PATH]")
      end

      it "handles messages with no sensitive data" do
        message = "Flag evaluation completed successfully"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Flag evaluation completed successfully")
      end

      it "handles empty messages" do
        result = described_class.sanitize("", enabled: true)
        expect(result).to eq("")
      end

      it "handles nil messages" do
        result = described_class.sanitize(nil, enabled: true)
        expect(result).to be_nil
      end
    end

    context "when sanitization is disabled" do
      it "returns the original message unchanged" do
        message = "Error at /home/user/secrets with key sdk_secret123456789"
        result = described_class.sanitize(message, enabled: false)
        expect(result).to eq(message)
      end

      it "handles nil messages when disabled" do
        result = described_class.sanitize(nil, enabled: false)
        expect(result).to be_nil
      end

      it "handles empty messages when disabled" do
        result = described_class.sanitize("", enabled: false)
        expect(result).to eq("")
      end
    end

    context "edge cases" do
      it "handles messages with only whitespace" do
        message = "   \n\t  "
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("   \n\t  ")
      end

      it "handles special characters that are not patterns" do
        message = "Error: [special] {brackets} <angles>"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("Error: [special] {brackets} <angles>")
      end

      it "preserves the structure of complex error messages" do
        message = "NetworkError: Failed to connect to api.flagkit.dev (timeout after 30s)"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("NetworkError: Failed to connect to api.flagkit.dev (timeout after 30s)")
      end

      it "handles adjacent sensitive values" do
        message = "sdk_key123456789 srv_key987654321"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("sdk_[REDACTED] srv_[REDACTED]")
      end

      it "handles paths with special characters" do
        message = "File /home/user/my-app_v2.0/config.json not found"
        result = described_class.sanitize(message, enabled: true)
        expect(result).to eq("File [PATH] not found")
      end

      it "does not modify the original string" do
        original = "Key: sdk_supersecretkey123"
        message = original.dup
        described_class.sanitize(message, enabled: true)
        expect(original).to eq("Key: sdk_supersecretkey123")
      end
    end
  end
end

RSpec.describe FlagKit::Error do
  before do
    # Store original settings
    @original_sanitization = described_class.sanitization_enabled
    @original_preserve = described_class.preserve_original
  end

  after do
    # Restore original settings
    described_class.sanitization_enabled = @original_sanitization
    described_class.preserve_original = @original_preserve
  end

  describe "error message sanitization" do
    context "when sanitization is enabled globally" do
      before do
        described_class.sanitization_enabled = true
        described_class.preserve_original = false
      end

      it "sanitizes error messages" do
        error = described_class.new("TEST_ERROR", "Failed at /home/user/app/config.json")
        expect(error.message).to eq("[TEST_ERROR] Failed at [PATH]")
      end

      it "sanitizes API keys in error messages" do
        error = described_class.new("AUTH_ERROR", "Invalid key: sdk_secretapikey123")
        expect(error.message).to eq("[AUTH_ERROR] Invalid key: sdk_[REDACTED]")
      end

      it "sanitizes multiple patterns" do
        error = described_class.new("ERROR", "User admin@test.com at 10.0.0.1")
        expect(error.message).to eq("[ERROR] User [EMAIL] at [IP]")
      end
    end

    context "when sanitization is disabled globally" do
      before do
        described_class.sanitization_enabled = false
      end

      it "does not sanitize error messages" do
        error = described_class.new("TEST_ERROR", "Failed at /home/user/secrets.json")
        expect(error.message).to eq("[TEST_ERROR] Failed at /home/user/secrets.json")
      end
    end

    context "when preserve_original is enabled" do
      before do
        described_class.sanitization_enabled = true
        described_class.preserve_original = true
      end

      it "stores the original message" do
        original = "Error with sdk_supersecret123456"
        error = described_class.new("TEST_ERROR", original)
        expect(error.original_message).to eq(original)
        expect(error.message).to eq("[TEST_ERROR] Error with sdk_[REDACTED]")
      end

      it "does not store original when not sanitized" do
        described_class.sanitization_enabled = false
        error = described_class.new("TEST_ERROR", "some message")
        expect(error.original_message).to be_nil
      end
    end

    context "with per-error sanitization override" do
      before do
        described_class.sanitization_enabled = true
      end

      it "allows disabling sanitization for specific error" do
        error = described_class.new("TEST_ERROR", "Path: /etc/passwd", sanitize: false)
        expect(error.message).to eq("[TEST_ERROR] Path: /etc/passwd")
      end

      it "allows enabling sanitization when globally disabled" do
        described_class.sanitization_enabled = false
        error = described_class.new("TEST_ERROR", "IP: 192.168.1.1", sanitize: true)
        expect(error.message).to eq("[TEST_ERROR] IP: [IP]")
      end
    end

    context "factory methods" do
      before do
        described_class.sanitization_enabled = true
      end

      it "sanitizes init_error messages" do
        error = described_class.init_error("Failed reading /var/secrets/key")
        expect(error.message).to include("[PATH]")
        expect(error.message).not_to include("/var/secrets/key")
      end

      it "sanitizes network_error messages" do
        error = described_class.network_error("Connection to 192.168.1.1 failed")
        expect(error.message).to include("[IP]")
        expect(error.message).not_to include("192.168.1.1")
      end

      it "sanitizes auth_error messages" do
        error = described_class.auth_error("AUTH_ERROR", "Invalid key sdk_abc123xyz789")
        expect(error.message).to include("sdk_[REDACTED]")
        expect(error.message).not_to include("sdk_abc123xyz789")
      end
    end
  end
end
