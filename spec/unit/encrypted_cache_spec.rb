# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Core::EncryptedCache do
  let(:api_key) { "sdk_test123456789abcdef" }
  let(:cache) { described_class.new(api_key: api_key, ttl: 300, max_size: 100) }

  describe "#initialize" do
    it "creates an encrypted cache instance" do
      expect(cache).to be_a(described_class)
    end

    it "reports encryption as available" do
      expect(cache.encryption_available?).to be true
    end

    it "sets ttl and max_size" do
      expect(cache.ttl).to eq(300)
      expect(cache.max_size).to eq(100)
    end
  end

  describe "#set and #get" do
    it "stores and retrieves string values" do
      cache.set("key1", "value1")
      expect(cache.get("key1")).to eq("value1")
    end

    it "stores and retrieves integer values" do
      cache.set("int_key", 42)
      expect(cache.get("int_key")).to eq(42)
    end

    it "stores and retrieves float values" do
      cache.set("float_key", 3.14)
      expect(cache.get("float_key")).to eq(3.14)
    end

    it "stores and retrieves boolean values" do
      cache.set("bool_true", true)
      cache.set("bool_false", false)
      expect(cache.get("bool_true")).to be true
      expect(cache.get("bool_false")).to be false
    end

    it "stores and retrieves nil values" do
      cache.set("nil_key", nil)
      expect(cache.get("nil_key")).to be_nil
    end

    it "stores and retrieves hashes" do
      data = { "name" => "test", "enabled" => true, "count" => 42 }
      cache.set("hash_key", data)
      expect(cache.get("hash_key")).to eq(data)
    end

    it "stores and retrieves arrays" do
      data = [1, 2, 3, "four", { "five" => 5 }]
      cache.set("array_key", data)
      expect(cache.get("array_key")).to eq(data)
    end

    it "stores and retrieves deeply nested structures" do
      data = {
        "level1" => {
          "level2" => {
            "level3" => {
              "value" => "deep",
              "array" => [1, { "nested" => true }]
            }
          }
        }
      }
      cache.set("nested_key", data)
      expect(cache.get("nested_key")).to eq(data)
    end

    it "returns nil for non-existent keys" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "overwrites existing values" do
      cache.set("key", "original")
      cache.set("key", "updated")
      expect(cache.get("key")).to eq("updated")
    end
  end

  describe "encryption verification" do
    it "actually encrypts data in underlying storage" do
      cache.set("secret_key", "super_secret_value")

      # Access internal cache to verify encryption
      internal_cache = cache.instance_variable_get(:@cache)
      raw_value = internal_cache.get("secret_key")

      # Should be JSON with encryption fields
      parsed = JSON.parse(raw_value)
      expect(parsed).to have_key("iv")
      expect(parsed).to have_key("data")
      expect(parsed).to have_key("tag")
      expect(parsed).to have_key("version")
      expect(parsed["version"]).to eq(1)

      # Plaintext should not appear in encrypted data
      expect(raw_value).not_to include("super_secret_value")
    end

    it "generates unique IVs for each encryption" do
      cache.set("key1", "same_value")
      cache.set("key2", "same_value")

      internal_cache = cache.instance_variable_get(:@cache)
      raw1 = JSON.parse(internal_cache.get("key1"))
      raw2 = JSON.parse(internal_cache.get("key2"))

      # IVs must be different
      expect(raw1["iv"]).not_to eq(raw2["iv"])
    end

    it "generates different ciphertext for same plaintext due to IV" do
      cache.set("key1", "identical_value")
      cache.set("key2", "identical_value")

      internal_cache = cache.instance_variable_get(:@cache)
      raw1 = JSON.parse(internal_cache.get("key1"))
      raw2 = JSON.parse(internal_cache.get("key2"))

      expect(raw1["data"]).not_to eq(raw2["data"])
    end
  end

  describe "#has?" do
    it "returns true for existing keys" do
      cache.set("exists", "value")
      expect(cache.has?("exists")).to be true
    end

    it "returns false for non-existent keys" do
      expect(cache.has?("not_exists")).to be false
    end
  end

  describe "#delete" do
    it "removes key from cache" do
      cache.set("to_delete", "value")
      result = cache.delete("to_delete")
      expect(result).to be true
      expect(cache.has?("to_delete")).to be false
    end

    it "returns false when deleting non-existent key" do
      expect(cache.delete("nonexistent")).to be false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.get("key1")).to be_nil
    end
  end

  describe "#size" do
    it "returns zero for empty cache" do
      expect(cache.size).to eq(0)
    end

    it "returns correct count of entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      expect(cache.size).to eq(2)
    end
  end

  describe "#keys" do
    it "returns empty array for empty cache" do
      expect(cache.keys).to eq([])
    end

    it "returns all keys" do
      cache.set("alpha", "a")
      cache.set("beta", "b")
      cache.set("gamma", "c")

      expect(cache.keys).to contain_exactly("alpha", "beta", "gamma")
    end
  end

  describe "#to_h" do
    it "returns all decrypted values as hash" do
      cache.set("key1", "value1")
      cache.set("key2", { "nested" => true })
      cache.set("key3", [1, 2, 3])

      result = cache.to_h

      expect(result).to eq(
        "key1" => "value1",
        "key2" => { "nested" => true },
        "key3" => [1, 2, 3]
      )
    end
  end

  describe "#set_all" do
    it "sets multiple key-value pairs" do
      cache.set_all(
        "batch1" => "value1",
        "batch2" => { "data" => true },
        "batch3" => [1, 2, 3]
      )

      expect(cache.get("batch1")).to eq("value1")
      expect(cache.get("batch2")).to eq({ "data" => true })
      expect(cache.get("batch3")).to eq([1, 2, 3])
    end
  end

  describe "key isolation" do
    it "data encrypted with one key cannot be decrypted with another" do
      cache1 = described_class.new(api_key: "sdk_key_alpha_123456789")
      cache2 = described_class.new(api_key: "sdk_key_beta_987654321")

      cache1.set("shared_key", "secret_data")

      # Copy raw encrypted data to cache2's internal storage
      raw_encrypted = cache1.instance_variable_get(:@cache).get("shared_key")
      cache2.instance_variable_get(:@cache).set("shared_key", raw_encrypted)

      # cache2 should not be able to decrypt (returns nil due to auth failure)
      expect(cache2.get("shared_key")).to be_nil
    end
  end

  describe "AES-256-GCM authentication" do
    it "detects tampering with ciphertext" do
      cache.set("test_key", "original_value")

      # Tamper with the encrypted data
      internal_cache = cache.instance_variable_get(:@cache)
      raw = internal_cache.get("test_key")
      parsed = JSON.parse(raw)

      # Modify one byte of the ciphertext
      decoded_data = Base64.strict_decode64(parsed["data"])
      if decoded_data.length > 0
        tampered = decoded_data.dup
        tampered[0] = (tampered[0].ord ^ 0xFF).chr
        parsed["data"] = Base64.strict_encode64(tampered)
        internal_cache.set("test_key", JSON.generate(parsed))
      end

      # Decryption should fail (return nil)
      expect(cache.get("test_key")).to be_nil
    end

    it "detects tampering with IV" do
      cache.set("test_key", "original_value")

      internal_cache = cache.instance_variable_get(:@cache)
      raw = internal_cache.get("test_key")
      parsed = JSON.parse(raw)

      # Modify the IV
      decoded_iv = Base64.strict_decode64(parsed["iv"])
      tampered_iv = decoded_iv.dup
      tampered_iv[0] = (tampered_iv[0].ord ^ 0xFF).chr
      parsed["iv"] = Base64.strict_encode64(tampered_iv)
      internal_cache.set("test_key", JSON.generate(parsed))

      # Decryption should fail
      expect(cache.get("test_key")).to be_nil
    end

    it "detects tampering with auth tag" do
      cache.set("test_key", "original_value")

      internal_cache = cache.instance_variable_get(:@cache)
      raw = internal_cache.get("test_key")
      parsed = JSON.parse(raw)

      # Modify the auth tag
      decoded_tag = Base64.strict_decode64(parsed["tag"])
      tampered_tag = decoded_tag.dup
      tampered_tag[0] = (tampered_tag[0].ord ^ 0xFF).chr
      parsed["tag"] = Base64.strict_encode64(tampered_tag)
      internal_cache.set("test_key", JSON.generate(parsed))

      # Decryption should fail
      expect(cache.get("test_key")).to be_nil
    end
  end

  describe "encryption versioning" do
    it "rejects data with unsupported version" do
      internal_cache = cache.instance_variable_get(:@cache)

      # Create fake encrypted data with wrong version
      fake_encrypted = JSON.generate({
        "iv" => Base64.strict_encode64("random_iv_123"),
        "data" => Base64.strict_encode64("fake_data"),
        "tag" => Base64.strict_encode64("fake_tag_1234567"),
        "version" => 999
      })

      internal_cache.set("versioned_key", fake_encrypted)

      # Should return nil due to unsupported version
      expect(cache.get("versioned_key")).to be_nil
    end
  end

  describe "with logger" do
    let(:mock_logger) { double("logger", warn: nil, debug: nil, info: nil) }
    let(:cache_with_logger) { described_class.new(api_key: api_key, logger: mock_logger) }

    it "logs warnings on decryption failure" do
      # Set up corrupted data
      internal_cache = cache_with_logger.instance_variable_get(:@cache)
      internal_cache.set("corrupted", "not_valid_json{{{")

      cache_with_logger.get("corrupted")

      expect(mock_logger).to have_received(:warn).with(a_string_matching(/Decryption failed/))
    end
  end
end
