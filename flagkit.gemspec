# frozen_string_literal: true

require_relative "lib/flagkit/version"

Gem::Specification.new do |spec|
  spec.name          = "flagkit"
  spec.version       = FlagKit::VERSION
  spec.authors       = ["FlagKit"]
  spec.email         = ["support@flagkit.dev"]

  spec.summary       = "Official Ruby SDK for FlagKit feature flag management"
  spec.description   = "FlagKit Ruby SDK enables feature flag evaluation with local caching, background polling, and analytics tracking."
  spec.homepage      = "https://github.com/flagkit/flagkit-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("lib/**/*") + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.0", "< 3.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "base64", "~> 0.2"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
