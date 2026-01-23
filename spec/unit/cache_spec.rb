# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::Cache do
  let(:cache) { described_class.new(ttl: 60, max_size: 10) }

  describe "#initialize" do
    it "sets default values" do
      default_cache = described_class.new
      expect(default_cache.ttl).to eq(300)
      expect(default_cache.max_size).to eq(1000)
    end

    it "accepts custom values" do
      expect(cache.ttl).to eq(60)
      expect(cache.max_size).to eq(10)
    end
  end

  describe "#set and #get" do
    it "stores and retrieves values" do
      cache.set("key1", "value1")
      expect(cache.get("key1")).to eq("value1")
    end

    it "returns nil for missing keys" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "updates last_accessed_at on get" do
      cache.set("key1", "value1")
      sleep(0.01)
      cache.get("key1")
      # Just verifying no error; internal state is private
    end
  end

  describe "#has?" do
    it "returns true for existing keys" do
      cache.set("key1", "value1")
      expect(cache.has?("key1")).to be true
    end

    it "returns false for missing keys" do
      expect(cache.has?("nonexistent")).to be false
    end
  end

  describe "#delete" do
    it "removes a key" do
      cache.set("key1", "value1")
      expect(cache.delete("key1")).to be true
      expect(cache.get("key1")).to be_nil
    end

    it "returns false for missing keys" do
      expect(cache.delete("nonexistent")).to be false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear
      expect(cache.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns the number of entries" do
      expect(cache.size).to eq(0)
      cache.set("key1", "value1")
      expect(cache.size).to eq(1)
      cache.set("key2", "value2")
      expect(cache.size).to eq(2)
    end
  end

  describe "#keys" do
    it "returns all keys" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      expect(cache.keys).to contain_exactly("key1", "key2")
    end
  end

  describe "#to_h" do
    it "returns all values as a hash" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      expect(cache.to_h).to eq("key1" => "value1", "key2" => "value2")
    end
  end

  describe "#set_all" do
    it "sets multiple values at once" do
      cache.set_all("key1" => "value1", "key2" => "value2")
      expect(cache.get("key1")).to eq("value1")
      expect(cache.get("key2")).to eq("value2")
    end
  end

  describe "TTL expiration" do
    it "expires entries after TTL" do
      short_cache = described_class.new(ttl: 0.1, max_size: 10)
      short_cache.set("key1", "value1")
      expect(short_cache.get("key1")).to eq("value1")
      sleep(0.15)
      expect(short_cache.get("key1")).to be_nil
    end

    it "removes expired entries on has?" do
      short_cache = described_class.new(ttl: 0.1, max_size: 10)
      short_cache.set("key1", "value1")
      sleep(0.15)
      expect(short_cache.has?("key1")).to be false
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entry when max_size reached" do
      small_cache = described_class.new(ttl: 60, max_size: 3)
      small_cache.set("key1", "value1")
      small_cache.set("key2", "value2")
      small_cache.set("key3", "value3")

      # Access key1 to make it most recently used
      small_cache.get("key1")

      # Add a new entry, should evict key2 (least recently used)
      small_cache.set("key4", "value4")

      expect(small_cache.get("key1")).to eq("value1")
      expect(small_cache.get("key2")).to be_nil
      expect(small_cache.get("key3")).to eq("value3")
      expect(small_cache.get("key4")).to eq("value4")
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do |i|
        Thread.new do
          100.times do |j|
            cache.set("key#{i}_#{j}", "value#{i}_#{j}")
            cache.get("key#{i}_#{j}")
          end
        end
      end
      threads.each(&:join)
      # Just verify no errors occurred
    end
  end
end
