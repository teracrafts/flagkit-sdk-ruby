# frozen_string_literal: true

module FlagKit
  module Error
    # Base exception for all FlagKit SDK errors.
    class FlagKitError < StandardError
      attr_reader :code, :details, :original_message

      class << self
        # @return [Boolean] Whether error sanitization is enabled
        attr_accessor :sanitization_enabled

        # @return [Boolean] Whether to preserve the original message
        attr_accessor :preserve_original
      end

      # Default sanitization settings
      @sanitization_enabled = true
      @preserve_original = false

      # @param code [String] The error code
      # @param message [String] The error message
      # @param cause [Exception, nil] The underlying cause
      # @param sanitize [Boolean, nil] Override sanitization setting for this error
      def initialize(code, message, cause: nil, sanitize: nil)
        @code = code
        @cause = cause
        @details = {}

        should_sanitize = sanitize.nil? ? self.class.sanitization_enabled : sanitize
        sanitized_message = FlagKit::ErrorSanitizer.sanitize(message, enabled: should_sanitize)

        @original_message = message if self.class.preserve_original && should_sanitize

        super("[#{code}] #{sanitized_message}")
      end

      # @return [Boolean] Whether the error is recoverable
      def recoverable?
        ErrorCode.recoverable?(code)
      end

      # @return [Exception, nil] The underlying cause
      def cause
        @cause || super
      end

      # Adds details to the error.
      #
      # @param details [Hash] The details to add
      # @return [self]
      def with_details(details)
        @details.merge!(details)
        self
      end

      class << self
        # Creates an initialization error.
        def init_error(message)
          new(ErrorCode::INIT_FAILED, message)
        end

        # Creates an authentication error.
        def auth_error(code, message)
          new(code, message)
        end

        # Creates a network error.
        def network_error(message, cause: nil)
          new(ErrorCode::NETWORK_ERROR, message, cause: cause)
        end

        # Creates an evaluation error.
        def eval_error(code, message)
          new(code, message)
        end

        # Creates a configuration error.
        def config_error(code, message)
          new(code, message)
        end

        # Creates a security error.
        def security_error(code, message)
          new(code, message)
        end
      end
    end
  end

  # Alias for backward compatibility - use Error as the class name
  Error = Error::FlagKitError

  # SecurityError for strict PII mode and other security violations
  class SecurityError < Error
  end
end
