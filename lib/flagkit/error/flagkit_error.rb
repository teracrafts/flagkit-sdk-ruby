# frozen_string_literal: true

module FlagKit
  module Error
    # Base exception for all FlagKit SDK errors.
    class FlagKitError < StandardError
      attr_reader :code, :details

      # @param code [String] The error code
      # @param message [String] The error message
      # @param cause [Exception, nil] The underlying cause
      def initialize(code, message, cause: nil)
        @code = code
        @cause = cause
        @details = {}
        super("[#{code}] #{message}")
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
