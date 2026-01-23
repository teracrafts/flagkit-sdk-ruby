# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::ErrorCode do
  describe "error codes" do
    it "defines all 31 error codes" do
      expect(FlagKit::ErrorCode::INIT_FAILED).to eq("INIT_FAILED")
      expect(FlagKit::ErrorCode::INIT_ALREADY_INITIALIZED).to eq("INIT_ALREADY_INITIALIZED")
      expect(FlagKit::ErrorCode::AUTH_INVALID_KEY).to eq("AUTH_INVALID_KEY")
      expect(FlagKit::ErrorCode::NETWORK_ERROR).to eq("NETWORK_ERROR")
      expect(FlagKit::ErrorCode::CIRCUIT_OPEN).to eq("CIRCUIT_OPEN")
      expect(FlagKit::ErrorCode::EVAL_FLAG_NOT_FOUND).to eq("EVAL_FLAG_NOT_FOUND")
    end
  end

  describe ".recoverable?" do
    it "returns true for recoverable errors" do
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::NETWORK_ERROR)).to be true
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::NETWORK_TIMEOUT)).to be true
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::CIRCUIT_OPEN)).to be true
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::CACHE_EXPIRED)).to be true
    end

    it "returns false for non-recoverable errors" do
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::INIT_FAILED)).to be false
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::AUTH_INVALID_KEY)).to be false
      expect(FlagKit::ErrorCode.recoverable?(FlagKit::ErrorCode::CONFIG_INVALID_API_KEY)).to be false
    end
  end
end
