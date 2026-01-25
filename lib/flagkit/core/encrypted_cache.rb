# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module FlagKit
  module Core
    # Encrypted cache wrapper using AES-256-GCM.
    #
    # Wraps the standard Cache and encrypts/decrypts values transparently.
    # Uses PBKDF2 to derive encryption key from API key.
    #
    # @example
    #   cache = EncryptedCache.new(api_key: "sdk_abc123", ttl: 300)
    #   cache.set("key", "secret value")
    #   cache.get("key") # => "secret value"
    class EncryptedCache
      # Encryption constants
      ENCRYPTION_VERSION = 1
      IV_LENGTH = 12       # 96 bits for GCM
      TAG_LENGTH = 16      # 128 bits for GCM
      KEY_LENGTH = 32      # 256 bits for AES-256
      PBKDF2_ITERATIONS = 100_000
      SALT = "FlagKit-v1-cache"

      attr_reader :ttl, :max_size

      # @param api_key [String] The API key used to derive encryption key
      # @param ttl [Integer] Time to live in seconds
      # @param max_size [Integer] Maximum number of entries
      # @param logger [Object, nil] Optional logger instance
      def initialize(api_key:, ttl: 300, max_size: 1000, logger: nil)
        @ttl = ttl
        @max_size = max_size
        @logger = logger
        @cache = Cache.new(ttl: ttl, max_size: max_size)
        @derived_key = derive_key(api_key)
        @encryption_available = !@derived_key.nil?
      end

      # Gets a value from the cache (decrypted).
      #
      # @param key [String] The cache key
      # @return [Object, nil] The decrypted cached value or nil
      def get(key)
        encrypted = @cache.get(key)
        return nil unless encrypted

        decrypt(encrypted)
      rescue StandardError => e
        log(:warn, "Decryption failed for key '#{key}': #{e.message}")
        nil
      end

      # Sets a value in the cache (encrypted).
      #
      # @param key [String] The cache key
      # @param value [Object] The value to cache (will be JSON serialized)
      def set(key, value)
        encrypted = encrypt(value)
        @cache.set(key, encrypted)
      rescue StandardError => e
        log(:warn, "Encryption failed for key '#{key}': #{e.message}")
        # Fall back to unencrypted storage
        @cache.set(key, JSON.generate({ _unencrypted: true, data: value }))
      end

      # Checks if a key exists in the cache.
      #
      # @param key [String] The cache key
      # @return [Boolean]
      def has?(key)
        @cache.has?(key)
      end

      # Deletes a value from the cache.
      #
      # @param key [String] The cache key
      # @return [Boolean] Whether the key existed
      def delete(key)
        @cache.delete(key)
      end

      # Clears all entries from the cache.
      def clear
        @cache.clear
      end

      # Returns the number of entries in the cache.
      #
      # @return [Integer]
      def size
        @cache.size
      end

      # Returns all keys in the cache.
      #
      # @return [Array<String>]
      def keys
        @cache.keys
      end

      # Gets all values from the cache (decrypted).
      #
      # @return [Hash]
      def to_h
        result = {}
        keys.each do |key|
          value = get(key)
          result[key] = value unless value.nil?
        end
        result
      end

      # Sets multiple values in the cache (encrypted).
      #
      # @param hash [Hash] The key-value pairs to cache
      def set_all(hash)
        hash.each { |key, value| set(key, value) }
      end

      # Checks if encryption is available.
      #
      # @return [Boolean]
      def encryption_available?
        @encryption_available
      end

      private

      # Derives the encryption key from the API key using PBKDF2.
      #
      # @param api_key [String] The API key
      # @return [String, nil] The derived key or nil if derivation fails
      def derive_key(api_key)
        OpenSSL::KDF.pbkdf2_hmac(
          api_key,
          salt: SALT,
          iterations: PBKDF2_ITERATIONS,
          length: KEY_LENGTH,
          hash: "SHA256"
        )
      rescue StandardError => e
        log(:warn, "Key derivation failed: #{e.message}")
        nil
      end

      # Encrypts data using AES-256-GCM.
      #
      # @param data [Object] The data to encrypt (will be JSON serialized)
      # @return [String] The encrypted data as JSON string
      def encrypt(data)
        unless @encryption_available
          # Fall back to unencrypted
          return JSON.generate({ _unencrypted: true, data: data })
        end

        plaintext = JSON.generate(data)

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = @derived_key
        iv = cipher.random_iv
        cipher.iv = iv

        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag(TAG_LENGTH)

        encrypted_data = {
          iv: Base64.strict_encode64(iv),
          data: Base64.strict_encode64(ciphertext),
          tag: Base64.strict_encode64(tag),
          version: ENCRYPTION_VERSION
        }

        JSON.generate(encrypted_data)
      end

      # Decrypts data using AES-256-GCM.
      #
      # @param encrypted [String] The encrypted data as JSON string
      # @return [Object] The decrypted data
      def decrypt(encrypted)
        parsed = JSON.parse(encrypted)

        # Handle unencrypted fallback data
        if parsed["_unencrypted"]
          return parsed["data"]
        end

        # Verify encryption version
        unless parsed["version"] == ENCRYPTION_VERSION
          log(:warn, "Unsupported encryption version: #{parsed['version']}")
          return nil
        end

        unless @encryption_available
          log(:warn, "Cannot decrypt: encryption not available")
          return nil
        end

        iv = Base64.strict_decode64(parsed["iv"])
        ciphertext = Base64.strict_decode64(parsed["data"])
        tag = Base64.strict_decode64(parsed["tag"])

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = @derived_key
        cipher.iv = iv
        cipher.auth_tag = tag

        plaintext = cipher.update(ciphertext) + cipher.final
        JSON.parse(plaintext)
      end

      def log(level, message)
        return unless @logger

        @logger.send(level, "[FlagKit::EncryptedCache] #{message}")
      end
    end
  end

  # Alias for backward compatibility
  EncryptedCache = Core::EncryptedCache
end
