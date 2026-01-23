# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::FlagState do
  describe "#initialize" do
    it "sets required values" do
      state = described_class.new(key: "my-flag", value: true)

      expect(state.key).to eq("my-flag")
      expect(state.value).to be true
      expect(state.enabled).to be true
      expect(state.version).to eq(0)
    end

    it "infers flag type from value" do
      expect(described_class.new(key: "f", value: true).flag_type).to eq(FlagKit::FlagType::BOOLEAN)
      expect(described_class.new(key: "f", value: "hello").flag_type).to eq(FlagKit::FlagType::STRING)
      expect(described_class.new(key: "f", value: 42).flag_type).to eq(FlagKit::FlagType::NUMBER)
      expect(described_class.new(key: "f", value: { a: 1 }).flag_type).to eq(FlagKit::FlagType::JSON)
    end
  end

  describe "value accessors" do
    describe "#boolean_value" do
      it "returns true for true value" do
        expect(described_class.new(key: "f", value: true).boolean_value).to be true
      end

      it "returns false for non-true values" do
        expect(described_class.new(key: "f", value: "true").boolean_value).to be false
        expect(described_class.new(key: "f", value: 1).boolean_value).to be false
      end
    end

    describe "#string_value" do
      it "returns string representation" do
        expect(described_class.new(key: "f", value: "hello").string_value).to eq("hello")
        expect(described_class.new(key: "f", value: 42).string_value).to eq("42")
      end

      it "returns nil for nil value" do
        expect(described_class.new(key: "f", value: nil).string_value).to be_nil
      end
    end

    describe "#number_value" do
      it "returns float for numeric values" do
        expect(described_class.new(key: "f", value: 42).number_value).to eq(42.0)
        expect(described_class.new(key: "f", value: 3.14).number_value).to eq(3.14)
      end

      it "returns 0.0 for non-numeric values" do
        expect(described_class.new(key: "f", value: "hello").number_value).to eq(0.0)
      end
    end

    describe "#int_value" do
      it "returns integer for numeric values" do
        expect(described_class.new(key: "f", value: 42.9).int_value).to eq(42)
      end

      it "returns 0 for non-numeric values" do
        expect(described_class.new(key: "f", value: "hello").int_value).to eq(0)
      end
    end

    describe "#json_value" do
      it "returns hash for hash values" do
        expect(described_class.new(key: "f", value: { a: 1 }).json_value).to eq({ a: 1 })
      end

      it "returns nil for non-hash values" do
        expect(described_class.new(key: "f", value: "hello").json_value).to be_nil
      end
    end
  end

  describe ".from_hash" do
    it "creates a FlagState from string-keyed hash" do
      state = described_class.from_hash({
        "key" => "my-flag",
        "value" => true,
        "enabled" => true,
        "version" => 5,
        "flagType" => "boolean"
      })

      expect(state.key).to eq("my-flag")
      expect(state.value).to be true
      expect(state.version).to eq(5)
    end

    it "creates a FlagState from symbol-keyed hash" do
      state = described_class.from_hash({
        key: "my-flag",
        value: "hello",
        enabled: false,
        version: 3
      })

      expect(state.key).to eq("my-flag")
      expect(state.value).to eq("hello")
      expect(state.enabled).to be false
    end
  end

  describe "#to_h" do
    it "converts to hash representation" do
      state = described_class.new(
        key: "my-flag",
        value: true,
        enabled: true,
        version: 1
      )

      hash = state.to_h

      expect(hash[:key]).to eq("my-flag")
      expect(hash[:value]).to be true
      expect(hash[:enabled]).to be true
      expect(hash[:version]).to eq(1)
    end
  end

  describe "#==" do
    it "returns true for equal states" do
      state1 = described_class.new(key: "f", value: true, version: 1)
      state2 = described_class.new(key: "f", value: true, version: 1)

      expect(state1).to eq(state2)
    end

    it "returns false for different states" do
      state1 = described_class.new(key: "f", value: true, version: 1)
      state2 = described_class.new(key: "f", value: true, version: 2)

      expect(state1).not_to eq(state2)
    end
  end
end
