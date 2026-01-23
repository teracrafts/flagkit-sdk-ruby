# frozen_string_literal: true

module FlagKit
  module Core
    # Thread-safe in-memory cache with TTL and LRU eviction.
    class Cache
      # Represents a cached entry with expiration.
      class Entry
        attr_reader :value, :expires_at
        attr_accessor :last_accessed_at

        def initialize(value, ttl_seconds)
          @value = value
          @expires_at = Time.now + ttl_seconds
          @last_accessed_at = Time.now
        end

        def expired?
          Time.now > expires_at
        end
      end

      attr_reader :ttl, :max_size

      # @param ttl [Integer] Time to live in seconds
      # @param max_size [Integer] Maximum number of entries
      def initialize(ttl: 300, max_size: 1000)
        @ttl = ttl
        @max_size = max_size
        @entries = {}
        @mutex = Mutex.new
      end

      # Gets a value from the cache.
      #
      # @param key [String] The cache key
      # @return [Object, nil] The cached value or nil
      def get(key)
        @mutex.synchronize do
          entry = @entries[key]
          return nil unless entry

          if entry.expired?
            @entries.delete(key)
            return nil
          end

          entry.last_accessed_at = Time.now
          entry.value
        end
      end

      # Sets a value in the cache.
      #
      # @param key [String] The cache key
      # @param value [Object] The value to cache
      def set(key, value)
        @mutex.synchronize do
          evict_if_needed
          @entries[key] = Entry.new(value, ttl)
        end
      end

      # Checks if a key exists in the cache.
      #
      # @param key [String] The cache key
      # @return [Boolean]
      def has?(key)
        @mutex.synchronize do
          entry = @entries[key]
          return false unless entry

          if entry.expired?
            @entries.delete(key)
            return false
          end

          true
        end
      end

      # Deletes a value from the cache.
      #
      # @param key [String] The cache key
      # @return [Boolean] Whether the key existed
      def delete(key)
        @mutex.synchronize do
          !@entries.delete(key).nil?
        end
      end

      # Clears all entries from the cache.
      def clear
        @mutex.synchronize do
          @entries.clear
        end
      end

      # Returns the number of entries in the cache.
      #
      # @return [Integer]
      def size
        @mutex.synchronize do
          cleanup_expired
          @entries.size
        end
      end

      # Returns all keys in the cache.
      #
      # @return [Array<String>]
      def keys
        @mutex.synchronize do
          cleanup_expired
          @entries.keys.dup
        end
      end

      # Gets all values from the cache.
      #
      # @return [Hash]
      def to_h
        @mutex.synchronize do
          cleanup_expired
          @entries.transform_values(&:value)
        end
      end

      # Sets multiple values in the cache.
      #
      # @param hash [Hash] The key-value pairs to cache
      def set_all(hash)
        @mutex.synchronize do
          hash.each do |key, value|
            evict_if_needed
            @entries[key] = Entry.new(value, ttl)
          end
        end
      end

      private

      def cleanup_expired
        @entries.delete_if { |_, entry| entry.expired? }
      end

      def evict_if_needed
        return if @entries.size < max_size

        cleanup_expired
        return if @entries.size < max_size

        # LRU eviction
        lru_key = @entries.min_by { |_, entry| entry.last_accessed_at }&.first
        @entries.delete(lru_key) if lru_key
      end
    end
  end

  # Alias for backward compatibility
  Cache = Core::Cache
end
