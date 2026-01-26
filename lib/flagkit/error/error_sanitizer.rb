# frozen_string_literal: true

module FlagKit
  module Error
    # Sanitizes error messages to remove sensitive information.
    #
    # This utility removes potentially sensitive data from error messages
    # to prevent information leakage in logs, error reports, and user-facing messages.
    module ErrorSanitizer
      # Patterns for sanitizing sensitive information.
      # Each entry is [pattern, replacement].
      PATTERNS = [
        # Unix-style paths
        [%r{/(?:[\w.-]+/)+[\w.-]+}, "[PATH]"],
        # Windows-style paths
        [/[A-Za-z]:\\(?:[\w.-]+\\)+[\w.-]*/, "[PATH]"],
        # IP addresses
        [/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "[IP]"],
        # SDK API keys
        [/sdk_[a-zA-Z0-9_-]{8,}/, "sdk_[REDACTED]"],
        # Server API keys
        [/srv_[a-zA-Z0-9_-]{8,}/, "srv_[REDACTED]"],
        # CLI API keys
        [/cli_[a-zA-Z0-9_-]{8,}/, "cli_[REDACTED]"],
        # Email addresses
        [/[\w.-]+@[\w.-]+\.\w+/, "[EMAIL]"],
        # Database connection strings
        [%r{(?:postgres|mysql|mongodb|redis)://[^\s]+}i, "[CONNECTION_STRING]"]
      ].freeze

      class << self
        # Sanitizes a message by removing sensitive information.
        #
        # @param message [String] The message to sanitize
        # @param enabled [Boolean] Whether sanitization is enabled
        # @return [String] The sanitized message
        def sanitize(message, enabled: true)
          return message unless enabled
          return message if message.nil? || message.empty?

          result = message.dup
          PATTERNS.each do |pattern, replacement|
            result.gsub!(pattern, replacement)
          end
          result
        end
      end
    end
  end

  # Alias for backward compatibility
  ErrorSanitizer = Error::ErrorSanitizer
end
