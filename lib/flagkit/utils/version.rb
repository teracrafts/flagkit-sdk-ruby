# frozen_string_literal: true

module FlagKit
  module Utils
    # Semantic version comparison utilities for SDK version metadata handling.
    #
    # These utilities are used to compare the current SDK version against
    # server-provided version requirements (min, recommended, latest).
    module Version
      # Maximum allowed value for version components (defensive limit).
      MAX_VERSION_COMPONENT = 999_999_999

      class << self
        # Parse a semantic version string into numeric components.
        # Returns nil if the version is not a valid semver.
        #
        # @param version [String] The version string to parse
        # @return [Hash, nil] Hash with :major, :minor, :patch keys, or nil if invalid
        #
        # @example
        #   Version.parse("1.2.3")    # => { major: 1, minor: 2, patch: 3 }
        #   Version.parse("v1.2.3")   # => { major: 1, minor: 2, patch: 3 }
        #   Version.parse("1.2.3-rc1") # => { major: 1, minor: 2, patch: 3 }
        #   Version.parse("invalid")  # => nil
        def parse(version)
          return nil if version.nil? || !version.is_a?(String)

          # Trim whitespace
          trimmed = version.strip
          return nil if trimmed.empty?

          # Strip leading 'v' or 'V' if present
          normalized = trimmed.start_with?("v", "V") ? trimmed[1..] : trimmed

          # Match semver pattern (allows pre-release suffix but ignores it for comparison)
          match = normalized.match(/^(\d+)\.(\d+)\.(\d+)/)
          return nil unless match

          major = match[1].to_i
          minor = match[2].to_i
          patch = match[3].to_i

          # Validate components are within reasonable bounds
          return nil if major.negative? || major > MAX_VERSION_COMPONENT
          return nil if minor.negative? || minor > MAX_VERSION_COMPONENT
          return nil if patch.negative? || patch > MAX_VERSION_COMPONENT

          {
            major: major,
            minor: minor,
            patch: patch
          }
        end

        # Compare two semantic versions.
        #
        # @param version_a [String] First version
        # @param version_b [String] Second version
        # @return [Integer] Negative if a < b, 0 if a == b, positive if a > b.
        #   Returns 0 if either version is invalid.
        #
        # @example
        #   Version.compare("1.0.0", "2.0.0")  # => -1
        #   Version.compare("2.0.0", "1.0.0")  # => 1
        #   Version.compare("1.0.0", "1.0.0")  # => 0
        def compare(version_a, version_b)
          parsed_a = parse(version_a)
          parsed_b = parse(version_b)

          return 0 if parsed_a.nil? || parsed_b.nil?

          # Compare major
          if parsed_a[:major] != parsed_b[:major]
            return parsed_a[:major] - parsed_b[:major]
          end

          # Compare minor
          if parsed_a[:minor] != parsed_b[:minor]
            return parsed_a[:minor] - parsed_b[:minor]
          end

          # Compare patch
          parsed_a[:patch] - parsed_b[:patch]
        end

        # Check if version a is less than version b.
        #
        # @param version_a [String] First version
        # @param version_b [String] Second version
        # @return [Boolean] true if a < b
        #
        # @example
        #   Version.less_than?("1.0.0", "2.0.0")  # => true
        #   Version.less_than?("2.0.0", "1.0.0")  # => false
        #   Version.less_than?("1.0.0", "1.0.0")  # => false
        def less_than?(version_a, version_b)
          compare(version_a, version_b).negative?
        end

        # Check if version a is greater than or equal to version b.
        #
        # @param version_a [String] First version
        # @param version_b [String] Second version
        # @return [Boolean] true if a >= b
        #
        # @example
        #   Version.at_least?("2.0.0", "1.0.0")  # => true
        #   Version.at_least?("1.0.0", "1.0.0")  # => true
        #   Version.at_least?("1.0.0", "2.0.0")  # => false
        def at_least?(version_a, version_b)
          compare(version_a, version_b) >= 0
        end
      end
    end
  end
end
