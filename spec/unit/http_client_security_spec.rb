# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Http::HttpClient, "Security Features" do
  let(:api_key) { "sdk_test123456789abcdef" }
  let(:secondary_api_key) { "sdk_secondary987654321" }
  let(:circuit_breaker) { FlagKit::CircuitBreaker.new(failure_threshold: 5, reset_timeout: 30) }

  describe ".get_base_url" do
    after do
      ENV.delete("FLAGKIT_MODE")
    end

    it "returns production URL by default" do
      ENV.delete("FLAGKIT_MODE")
      expect(described_class.get_base_url).to eq("https://api.flagkit.dev/api/v1")
    end

    it "returns local URL when FLAGKIT_MODE=local" do
      ENV["FLAGKIT_MODE"] = "local"
      expect(described_class.get_base_url).to eq("https://api.flagkit.on/api/v1")
    end

    it "returns beta URL when FLAGKIT_MODE=beta" do
      ENV["FLAGKIT_MODE"] = "beta"
      expect(described_class.get_base_url).to eq("https://api.beta.flagkit.dev/api/v1")
    end

    it "is case-insensitive" do
      ENV["FLAGKIT_MODE"] = "LOCAL"
      expect(described_class.get_base_url).to eq("https://api.flagkit.on/api/v1")
    end

    it "trims whitespace" do
      ENV["FLAGKIT_MODE"] = " local "
      expect(described_class.get_base_url).to eq("https://api.flagkit.on/api/v1")
    end

    it "falls through to production for unknown mode" do
      ENV["FLAGKIT_MODE"] = "staging"
      expect(described_class.get_base_url).to eq("https://api.flagkit.dev/api/v1")
    end
  end

  describe "request signing" do
    let(:http_client) do
      described_class.new(
        api_key: api_key,
        timeout: 5,
        retry_attempts: 1,
        circuit_breaker: circuit_breaker,
        enable_request_signing: true
      )
    end

    before do
      stub_request(:post, %r{api\.flagkit\.dev.*sdk/evaluate})
        .to_return(status: 200, body: '{"key":"test","enabled":true}', headers: { "Content-Type" => "application/json" })
    end

    it "adds X-Signature header to POST requests" do
      http_client.post("sdk/evaluate", { key: "test" })

      expect(WebMock).to have_requested(:post, %r{sdk/evaluate})
        .with { |req| req.headers.key?("X-Signature") }
    end

    it "adds X-Timestamp header to POST requests" do
      http_client.post("sdk/evaluate", { key: "test" })

      expect(WebMock).to have_requested(:post, %r{sdk/evaluate})
        .with { |req| req.headers.key?("X-Timestamp") }
    end

    it "adds X-Key-Id header to POST requests" do
      http_client.post("sdk/evaluate", { key: "test" })

      expect(WebMock).to have_requested(:post, %r{sdk/evaluate})
        .with { |req| req.headers["X-Key-Id"] == "sdk_test" }
    end

    it "does not add signing headers when request signing is disabled" do
      http_client_no_signing = described_class.new(
        api_key: api_key,
        timeout: 5,
        retry_attempts: 1,
        circuit_breaker: circuit_breaker,
        enable_request_signing: false
      )

      http_client_no_signing.post("sdk/evaluate", { key: "test" })

      expect(WebMock).to have_requested(:post, %r{sdk/evaluate})
        .with { |req| !req.headers.key?("X-Signature") }
    end

    it "does not add signing headers for empty body" do
      http_client.post("sdk/evaluate", {})

      expect(WebMock).to have_requested(:post, %r{sdk/evaluate})
        .with { |req| !req.headers.key?("X-Signature") }
    end
  end

  describe "key rotation" do
    let(:http_client) do
      described_class.new(
        api_key: api_key,
        timeout: 5,
        retry_attempts: 1,
        circuit_breaker: circuit_breaker,
        secondary_api_key: secondary_api_key,
        key_rotation_grace_period: 300
      )
    end

    it "starts with primary API key" do
      expect(http_client.api_key).to eq(api_key)
    end

    it "reports key_id correctly" do
      expect(http_client.key_id).to eq("sdk_test")
    end

    it "is not in key rotation initially" do
      expect(http_client.in_key_rotation?).to be false
    end

    context "when primary key fails with 401" do
      before do
        # First request fails with 401
        stub_request(:get, %r{api\.flagkit\.dev.*sdk/init})
          .with(headers: { "X-API-Key" => api_key })
          .to_return(status: 401, body: '{"error":"Invalid API key"}')

        # Second request with secondary key succeeds
        stub_request(:get, %r{api\.flagkit\.dev.*sdk/init})
          .with(headers: { "X-API-Key" => secondary_api_key })
          .to_return(status: 200, body: '{"flags":[]}', headers: { "Content-Type" => "application/json" })
      end

      it "rotates to secondary key on 401 error" do
        http_client.get("sdk/init")

        expect(http_client.api_key).to eq(secondary_api_key)
      end

      it "reports being in key rotation" do
        http_client.get("sdk/init")

        expect(http_client.in_key_rotation?).to be true
      end
    end

    context "when no secondary key is configured" do
      let(:http_client_no_secondary) do
        described_class.new(
          api_key: api_key,
          timeout: 5,
          retry_attempts: 1,
          circuit_breaker: circuit_breaker,
          secondary_api_key: nil
        )
      end

      before do
        stub_request(:get, %r{api\.flagkit\.dev.*sdk/init})
          .to_return(status: 401, body: '{"error":"Invalid API key"}')
      end

      it "raises error without rotation attempt" do
        error = nil
        begin
          http_client_no_secondary.get("sdk/init")
        rescue StandardError => e
          error = e
        end
        expect(error).not_to be_nil
        expect(error.message).to include("Invalid API key")
      end
    end

    context "when both keys fail" do
      before do
        stub_request(:get, %r{api\.flagkit\.dev.*sdk/init})
          .to_return(status: 401, body: '{"error":"Invalid API key"}')
      end

      it "raises error after trying both keys" do
        error = nil
        begin
          http_client.get("sdk/init")
        rescue StandardError => e
          error = e
        end
        expect(error).not_to be_nil
        expect(error.message).to include("Invalid API key")
      end
    end
  end

  describe "key_id helper method" do
    let(:http_client) do
      described_class.new(
        api_key: "srv_verylongapikey123456789",
        timeout: 5,
        retry_attempts: 1,
        circuit_breaker: circuit_breaker
      )
    end

    it "returns the first 8 characters of the API key" do
      expect(http_client.key_id).to eq("srv_very")
    end
  end
end
