# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module FlagKit
  module Utils
    # Security utilities for FlagKit SDK.
    #
    # Provides methods for detecting potential PII in data,
    # validating API key usage, request signing with HMAC-SHA256,
    # and cache encryption with AES-256-GCM.
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
        # @param strict_mode [Boolean] When true, raises SecurityError instead of warning
        # @param has_private_attributes [Boolean] Whether private_attributes are configured
        # @return [void]
        # @raise [FlagKit::SecurityError] In strict mode when PII detected without private_attributes
        #
        # @example
        #   Security.warn_if_potential_pii({ email: "test@example.com" }, :context, logger)
        def warn_if_potential_pii(data, data_type, logger = nil, strict_mode: false, has_private_attributes: false)
          return if data.nil?

          pii_fields = detect_potential_pii(data)
          return if pii_fields.empty?

          # In strict mode, raise error if PII detected without private_attributes
          if strict_mode && !has_private_attributes
            raise FlagKit::SecurityError.new(
              FlagKit::ErrorCode::SECURITY_PII_DETECTED,
              "Potential PII detected in #{data_type} data: #{pii_fields.join(', ')}. " \
              "In strict_pii_mode, you must configure private_attributes for PII fields or remove the data."
            )
          end

          return unless config.warn_on_potential_pii
          return if logger.nil?

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

        # Gets the first 8 characters of an API key for identification.
        # This is safe to expose as it doesn't reveal the full key.
        #
        # @param api_key [String] The API key
        # @return [String] The key identifier (first 8 characters)
        #
        # @example
        #   Security.get_key_id("sdk_abc123xyz") # => "sdk_abc1"
        def get_key_id(api_key)
          return "" if api_key.nil?

          api_key.to_s[0, 8]
        end

        # Generates an HMAC-SHA256 signature.
        #
        # @param message [String] The message to sign
        # @param key [String] The signing key
        # @return [String] The hex-encoded signature
        #
        # @example
        #   signature = Security.generate_hmac_sha256("message", "secret")
        def generate_hmac_sha256(message, key)
          OpenSSL::HMAC.hexdigest("SHA256", key, message)
        end

        # Creates a request signature for POST request bodies.
        # Format: timestamp.body
        #
        # @param body [String] The request body (JSON string)
        # @param api_key [String] The API key for signing
        # @param timestamp [Integer, nil] Optional timestamp in milliseconds
        # @return [Hash] Hash containing :signature, :timestamp, and :key_id
        #
        # @example
        #   result = Security.create_request_signature('{"key":"value"}', "sdk_abc123")
        #   # => { signature: "abc123...", timestamp: 1234567890, key_id: "sdk_abc1" }
        def create_request_signature(body, api_key, timestamp: nil)
          ts = timestamp || (Time.now.to_f * 1000).to_i
          message = "#{ts}.#{body}"
          signature = generate_hmac_sha256(message, api_key)

          {
            signature: signature,
            timestamp: ts,
            key_id: get_key_id(api_key)
          }
        end

        # Signs a payload with HMAC-SHA256.
        #
        # @param data [Object] The data to sign (will be JSON encoded)
        # @param api_key [String] The API key for signing
        # @param timestamp [Integer, nil] Optional timestamp in milliseconds
        # @return [Hash] Signed payload with :data, :signature, :timestamp, :key_id
        #
        # @example
        #   signed = Security.sign_payload({ events: [] }, "sdk_abc123")
        def sign_payload(data, api_key, timestamp: nil)
          ts = timestamp || (Time.now.to_f * 1000).to_i
          payload = JSON.generate(data)
          message = "#{ts}.#{payload}"
          signature = generate_hmac_sha256(message, api_key)

          {
            data: data,
            signature: signature,
            timestamp: ts,
            key_id: get_key_id(api_key)
          }
        end

        # Verifies a signed payload.
        #
        # @param signed_payload [Hash] The signed payload to verify
        # @param api_key [String] The API key for verification
        # @param max_age_ms [Integer] Maximum age in milliseconds (default: 5 minutes)
        # @return [Boolean] true if the signature is valid
        #
        # @example
        #   Security.verify_signed_payload(signed, "sdk_abc123")
        def verify_signed_payload(signed_payload, api_key, max_age_ms: 300_000)
          # Check timestamp age
          age = (Time.now.to_f * 1000).to_i - signed_payload[:timestamp]
          return false if age > max_age_ms || age.negative?

          # Verify key ID matches
          return false if signed_payload[:key_id] != get_key_id(api_key)

          # Verify signature
          payload = JSON.generate(signed_payload[:data])
          message = "#{signed_payload[:timestamp]}.#{payload}"
          expected_signature = generate_hmac_sha256(message, api_key)

          signed_payload[:signature] == expected_signature
        end

        # Canonicalizes an object by sorting keys recursively.
        # This ensures consistent JSON output for signature verification.
        #
        # @param obj [Object] The object to canonicalize
        # @return [String] Canonical JSON string representation
        #
        # @example
        #   Security.canonicalize_object({ b: 2, a: 1 }) # => '{"a":1,"b":2}'
        def canonicalize_object(obj)
          JSON.generate(deep_sort_keys(obj))
        end

        # Verifies an HMAC-SHA256 signature for bootstrap data.
        #
        # @param bootstrap [Hash] The bootstrap data with :flags, :signature, :timestamp
        # @param api_key [String] The API key for verification
        # @param max_age_ms [Integer] Maximum age in milliseconds (default: 24 hours)
        # @return [Hash] Result hash with :valid (Boolean) and :error (String or nil)
        def verify_bootstrap_signature(bootstrap, api_key, max_age_ms: 86_400_000)
          bootstrap = normalize_keys(bootstrap)

          error = validate_bootstrap_fields(bootstrap) || validate_bootstrap_timestamp(bootstrap, max_age_ms)
          return { valid: false, error: error } if error

          verify_bootstrap_hmac(bootstrap, api_key)
        end

        private

        # Validates required bootstrap fields are present.
        def validate_bootstrap_fields(bootstrap)
          return "Missing signature" unless bootstrap[:signature]
          return "Missing timestamp" unless bootstrap[:timestamp]
          return "Missing flags" unless bootstrap[:flags]

          nil
        end

        # Validates bootstrap timestamp is within acceptable age range.
        def validate_bootstrap_timestamp(bootstrap, max_age_ms)
          timestamp = bootstrap[:timestamp].to_i
          age = (Time.now.to_f * 1000).to_i - timestamp

          return "Bootstrap data expired (age: #{age}ms, max: #{max_age_ms}ms)" if age > max_age_ms
          return "Bootstrap timestamp is in the future" if age.negative?

          nil
        end

        # Computes and verifies the HMAC signature for bootstrap data.
        def verify_bootstrap_hmac(bootstrap, api_key)
          canonical_flags = canonicalize_object(bootstrap[:flags])
          message = "#{bootstrap[:timestamp]}.#{canonical_flags}"
          expected = generate_hmac_sha256(message, api_key)

          if secure_compare(expected, bootstrap[:signature].to_s)
            { valid: true, error: nil }
          else
            { valid: false, error: "Invalid signature" }
          end
        end

        # Performs constant-time string comparison to prevent timing attacks.
        #
        # @param a [String] First string
        # @param b [String] Second string
        # @return [Boolean] true if strings are equal
        def secure_compare(expected, actual)
          return false unless expected.bytesize == actual.bytesize

          # Use OpenSSL's fixed_length_secure_compare for constant-time comparison
          OpenSSL.fixed_length_secure_compare(expected, actual)
        rescue NoMethodError
          # Fallback for older Ruby versions without fixed_length_secure_compare
          # This is a constant-time comparison implementation
          l = expected.unpack("C*")
          r = actual.unpack("C*")
          result = 0
          l.zip(r) { |x, y| result |= x ^ y }
          result.zero?
        end

        # Recursively sorts hash keys for canonical representation.
        #
        # @param obj [Object] The object to process
        # @return [Object] Object with sorted keys
        def deep_sort_keys(obj)
          case obj
          when Hash
            obj.keys.sort_by(&:to_s).each_with_object({}) do |key, sorted|
              sorted[key] = deep_sort_keys(obj[key])
            end
          when Array
            obj.map { |item| deep_sort_keys(item) }
          else
            obj
          end
        end

        # Normalizes hash keys to symbols.
        #
        # @param hash [Hash] The hash to normalize
        # @return [Hash] Hash with symbol keys
        def normalize_keys(hash)
          return hash unless hash.is_a?(Hash)

          hash.transform_keys { |key| key.to_sym rescue key }
        end

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
