# frozen_string_literal: true

require "spec_helper"
require "flagkit/utils/version"

RSpec.describe FlagKit::Utils::Version do
  describe ".parse" do
    it "parses valid semver string" do
      result = described_class.parse("1.2.3")
      expect(result).to eq(major: 1, minor: 2, patch: 3)
    end

    it "parses zero version" do
      result = described_class.parse("0.0.0")
      expect(result).to eq(major: 0, minor: 0, patch: 0)
    end

    it "handles lowercase v prefix" do
      result = described_class.parse("v1.2.3")
      expect(result[:major]).to eq(1)
    end

    it "handles uppercase V prefix" do
      result = described_class.parse("V1.2.3")
      expect(result[:major]).to eq(1)
    end

    it "handles prerelease suffix" do
      result = described_class.parse("1.2.3-beta.1")
      expect(result).to eq(major: 1, minor: 2, patch: 3)
    end

    it "handles build metadata" do
      result = described_class.parse("1.2.3+build.123")
      expect(result[:patch]).to eq(3)
    end

    it "handles leading whitespace" do
      result = described_class.parse("  1.2.3")
      expect(result[:major]).to eq(1)
    end

    it "handles trailing whitespace" do
      result = described_class.parse("1.2.3  ")
      expect(result[:major]).to eq(1)
    end

    it "handles surrounding whitespace" do
      result = described_class.parse("  1.2.3  ")
      expect(result[:major]).to eq(1)
    end

    it "handles v prefix with whitespace" do
      result = described_class.parse("  v1.0.0  ")
      expect(result[:major]).to eq(1)
    end

    it "returns nil for nil input" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.parse("")).to be_nil
    end

    it "returns nil for whitespace only" do
      expect(described_class.parse("   ")).to be_nil
    end

    it "returns nil for invalid version" do
      expect(described_class.parse("invalid")).to be_nil
    end

    it "returns nil for partial version" do
      expect(described_class.parse("1.2")).to be_nil
    end

    it "returns nil for non-numeric components" do
      expect(described_class.parse("a.b.c")).to be_nil
    end

    it "returns nil for version exceeding max" do
      expect(described_class.parse("1000000000.0.0")).to be_nil
    end

    it "parses version at max boundary" do
      result = described_class.parse("999999999.999999999.999999999")
      expect(result[:major]).to eq(999999999)
    end

    it "returns nil for non-string input" do
      expect(described_class.parse(123)).to be_nil
    end
  end

  describe ".compare" do
    it "returns 0 for equal versions" do
      expect(described_class.compare("1.0.0", "1.0.0")).to eq(0)
    end

    it "returns 0 for equal versions with v prefix" do
      expect(described_class.compare("v1.0.0", "1.0.0")).to eq(0)
    end

    it "returns negative for a < b (major)" do
      expect(described_class.compare("1.0.0", "2.0.0")).to be < 0
    end

    it "returns negative for a < b (minor)" do
      expect(described_class.compare("1.0.0", "1.1.0")).to be < 0
    end

    it "returns negative for a < b (patch)" do
      expect(described_class.compare("1.0.0", "1.0.1")).to be < 0
    end

    it "returns positive for a > b" do
      expect(described_class.compare("2.0.0", "1.0.0")).to be > 0
    end

    it "returns 0 for invalid versions" do
      expect(described_class.compare("invalid", "1.0.0")).to eq(0)
      expect(described_class.compare("1.0.0", "invalid")).to eq(0)
    end
  end

  describe ".less_than?" do
    it "returns true when a < b" do
      expect(described_class.less_than?("1.0.0", "1.0.1")).to be true
      expect(described_class.less_than?("1.0.0", "1.1.0")).to be true
      expect(described_class.less_than?("1.0.0", "2.0.0")).to be true
    end

    it "returns false when a >= b" do
      expect(described_class.less_than?("1.0.0", "1.0.0")).to be false
      expect(described_class.less_than?("1.1.0", "1.0.0")).to be false
    end

    it "returns false for invalid versions" do
      expect(described_class.less_than?("invalid", "1.0.0")).to be false
    end
  end

  describe ".at_least?" do
    it "returns true when a >= b" do
      expect(described_class.at_least?("1.0.0", "1.0.0")).to be true
      expect(described_class.at_least?("1.1.0", "1.0.0")).to be true
      expect(described_class.at_least?("2.0.0", "1.0.0")).to be true
    end

    it "returns false when a < b" do
      expect(described_class.at_least?("1.0.0", "1.0.1")).to be false
    end
  end

  describe "SDK scenarios" do
    it "detects SDK below minimum" do
      sdk_version = "1.0.0"
      min_version = "1.1.0"
      expect(described_class.less_than?(sdk_version, min_version)).to be true
    end

    it "allows SDK at minimum" do
      sdk_version = "1.1.0"
      min_version = "1.1.0"
      expect(described_class.less_than?(sdk_version, min_version)).to be false
    end

    it "handles server v-prefixed response" do
      sdk_version = "1.0.0"
      server_min = "v1.1.0"
      expect(described_class.less_than?(sdk_version, server_min)).to be true
    end
  end
end
