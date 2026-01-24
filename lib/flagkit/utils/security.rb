# frozen_string_literal: true

module FlagKit
  module Utils
    # Security utilities for FlagKit SDK.
    #
    # Provides methods for detecting potential PII in data and
    # validating API key usage in different environments.
    module Security
      # Common PII field patterns (case-insensitive)
      PII_PATTERNS = %w[
        email
        phone
        telephone
        mobile
        ssn
        social_security
        socialSecurity
        credit_card
        creditCard
        card_number
        cardNumber
        cvv
        password
        passwd
        secret
        token
        api_key
        apiKey
        private_key
        privateKey
        access_token
        accessToken
        refresh_token
        refreshToken
        auth_token
        authToken
        address
        street
        zip_code
        zipCode
        postal_code
        postalCode
        date_of_birth
        dateOfBirth
        dob
        birth_date
        birthDate
        passport
        driver_license
        driverLicense
        national_id
        nationalId
        bank_account
        bankAccount
        routing_number
        routingNumber
        iban
        swift
      ].freeze

      class << self
        # Checks if a field name potentially contains PII.
        #
        # @param field_name [String] The field name to check
        # @return [Boolean] true if the field name matches a PII pattern
        #
        # @example
        #   Security.potential_pii_field?("email") # => true
        #   Security.potential_pii_field?("userEmail") # => true
        #   Security.potential_pii_field?("plan") # => false
        def potential_pii_field?(field_name)
          return false if field_name.nil?

          lower_name = field_name.to_s.downcase
          patterns = config.additional_pii_patterns + PII_PATTERNS
          patterns.any? { |pattern| lower_name.include?(pattern.downcase) }
        end

        # Detects potential PII in an object and returns the field paths.
        #
        # @param data [Hash] The data to scan for PII
        # @param prefix [String] Optional prefix for nested field paths
        # @return [Array<String>] Array of field paths that may contain PII
        #
        # @example
        #   data = { email: "user@example.com", plan: "premium" }
        #   Security.detect_potential_pii(data) # => ["email"]
        #
        # @example Nested data
        #   data = { user: { email: "test@example.com" } }
        #   Security.detect_potential_pii(data) # => ["user.email"]
        def detect_potential_pii(data, prefix = "")
          return [] unless data.is_a?(Hash)

          pii_fields = []

          data.each do |key, value|
            key_str = key.to_s
            full_path = prefix.empty? ? key_str : "#{prefix}.#{key_str}"

            pii_fields << full_path if potential_pii_field?(key_str)

            # Recursively check nested hashes
            if value.is_a?(Hash)
              nested_pii = detect_potential_pii(value, full_path)
              pii_fields.concat(nested_pii)
            end
          end

          pii_fields
        end

        # Warns about potential PII in data.
        #
        # @param data [Hash, nil] The data to check
        # @param data_type [String, Symbol] The type of data ("context" or "event")
        # @param logger [Object, nil] Optional logger instance
        # @return [void]
        #
        # @example
        #   Security.warn_if_potential_pii({ email: "test@example.com" }, :context, logger)
        def warn_if_potential_pii(data, data_type, logger = nil)
          return unless config.warn_on_potential_pii
          return if data.nil? || logger.nil?

          pii_fields = detect_potential_pii(data)
          return if pii_fields.empty?

          advice = case data_type.to_s
                   when "context"
                     "Consider adding these to privateAttributes."
                   else
                     "Consider removing sensitive data from events."
                   end

          message = "[FlagKit Security] Potential PII detected in #{data_type} data: " \
                    "#{pii_fields.join(', ')}. #{advice}"

          logger.warn(message) if logger.respond_to?(:warn)
        end

        # Checks if an API key is a server key.
        #
        # @param api_key [String] The API key to check
        # @return [Boolean] true if the key starts with "srv_"
        #
        # @example
        #   Security.server_key?("srv_abc123") # => true
        #   Security.server_key?("sdk_abc123") # => false
        def server_key?(api_key)
          return false if api_key.nil?

          api_key.to_s.start_with?("srv_")
        end

        # Checks if an API key is a client/SDK key.
        #
        # @param api_key [String] The API key to check
        # @return [Boolean] true if the key starts with "sdk_" or "cli_"
        #
        # @example
        #   Security.client_key?("sdk_abc123") # => true
        #   Security.client_key?("cli_abc123") # => true
        #   Security.client_key?("srv_abc123") # => false
        def client_key?(api_key)
          return false if api_key.nil?

          key_str = api_key.to_s
          key_str.start_with?("sdk_") || key_str.start_with?("cli_")
        end

        # Warns if a server key is used in a browser-like environment.
        #
        # In Ruby, this primarily applies to environments where JavaScript
        # is generated or where code might be exposed to clients (e.g., Rails
        # views with JavaScript, Opal, or similar).
        #
        # @param api_key [String] The API key to check
        # @param logger [Object, nil] Optional logger instance
        # @return [void]
        #
        # @example
        #   Security.warn_if_server_key_in_browser("srv_abc123", logger)
        def warn_if_server_key_in_browser(api_key, logger = nil)
          return unless config.warn_on_server_key_in_browser
          return unless browser_like_environment? && server_key?(api_key)

          message = "[FlagKit Security] WARNING: Server keys (srv_) should not be used in browser environments. " \
                    "This exposes your server key in client-side code, which is a security risk. " \
                    "Use SDK keys (sdk_) for client-side applications instead. " \
                    "See: https://docs.flagkit.dev/sdk/security#api-keys"

          # Always output to stderr for visibility
          warn message

          # Also log through the SDK logger if available
          logger.warn(message) if logger.respond_to?(:warn)
        end

        # Returns the current security configuration.
        #
        # @return [SecurityConfig] The current configuration
        def config
          @config ||= SecurityConfig.new
        end

        # Configures security settings.
        #
        # @yield [SecurityConfig] The configuration object to modify
        # @return [SecurityConfig] The updated configuration
        #
        # @example
        #   Security.configure do |config|
        #     config.warn_on_potential_pii = true
        #     config.additional_pii_patterns = ["custom_field"]
        #   end
        def configure
          yield config if block_given?
          config
        end

        # Resets configuration to defaults.
        #
        # @return [SecurityConfig] A new default configuration
        def reset_config!
          @config = SecurityConfig.new
        end

        private

        # Checks if we're in a browser-like environment.
        #
        # For Ruby, this checks for common indicators that code might
        # be running in or generating client-side JavaScript:
        # - Opal (Ruby to JavaScript compiler)
        # - Browser gem
        # - Environment variables indicating client-side context
        #
        # @return [Boolean] true if in a browser-like environment
        def browser_like_environment?
          # Check for Opal (Ruby compiled to JavaScript running in browser)
          return true if defined?(RUBY_ENGINE) && RUBY_ENGINE == "opal"

          # Check for environment variable that indicates browser context
          return true if ENV["FLAGKIT_BROWSER_CONTEXT"] == "true"

          false
        end
      end
    end

    # Security configuration options.
    #
    # @example
    #   config = SecurityConfig.new
    #   config.warn_on_potential_pii = true
    #   config.additional_pii_patterns = ["employee_id"]
    class SecurityConfig
      # @return [Boolean] Whether to warn about potential PII in context/events.
      #   Default: true in development, false in production
      attr_accessor :warn_on_potential_pii

      # @return [Boolean] Whether to warn when server keys are used in browser.
      #   Default: true
      attr_accessor :warn_on_server_key_in_browser

      # @return [Array<String>] Custom PII patterns to detect in addition to defaults
      attr_accessor :additional_pii_patterns

      # Creates a new SecurityConfig with default values.
      #
      # @param warn_on_potential_pii [Boolean] Enable PII warnings
      # @param warn_on_server_key_in_browser [Boolean] Enable server key warnings
      # @param additional_pii_patterns [Array<String>] Additional PII patterns
      def initialize(
        warn_on_potential_pii: default_warn_on_pii,
        warn_on_server_key_in_browser: true,
        additional_pii_patterns: []
      )
        @warn_on_potential_pii = warn_on_potential_pii
        @warn_on_server_key_in_browser = warn_on_server_key_in_browser
        @additional_pii_patterns = additional_pii_patterns
      end

      # Returns a hash representation of the configuration.
      #
      # @return [Hash] The configuration as a hash
      def to_h
        {
          warn_on_potential_pii: warn_on_potential_pii,
          warn_on_server_key_in_browser: warn_on_server_key_in_browser,
          additional_pii_patterns: additional_pii_patterns
        }
      end

      private

      def default_warn_on_pii
        env = ENV.fetch("RUBY_ENV", ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development")))
        env != "production"
      end
    end
  end
end
