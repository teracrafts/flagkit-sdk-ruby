# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlagKit::EvaluationContext do
  describe "#initialize" do
    it "creates an empty context" do
      context = described_class.new
      expect(context.user_id).to be_nil
      expect(context.attributes).to eq({})
    end

    it "creates a context with user_id" do
      context = described_class.new(user_id: "user-123")
      expect(context.user_id).to eq("user-123")
    end

    it "creates a context with attributes" do
      context = described_class.new(email: "test@example.com", plan: "pro")
      expect(context.attributes).to eq("email" => "test@example.com", "plan" => "pro")
    end

    it "converts symbol keys to strings" do
      context = described_class.new(foo: "bar")
      expect(context.attributes).to eq("foo" => "bar")
    end
  end

  describe "#with_user_id" do
    it "returns a new context with the user_id set" do
      context = described_class.new(email: "test@example.com")
      new_context = context.with_user_id("user-456")

      expect(new_context.user_id).to eq("user-456")
      expect(new_context.attributes).to eq("email" => "test@example.com")
      expect(context.user_id).to be_nil # Original unchanged
    end
  end

  describe "#with_attribute" do
    it "returns a new context with the attribute added" do
      context = described_class.new(user_id: "user-123")
      new_context = context.with_attribute(:plan, "enterprise")

      expect(new_context["plan"]).to eq("enterprise")
      expect(context["plan"]).to be_nil
    end
  end

  describe "#with_attributes" do
    it "returns a new context with multiple attributes added" do
      context = described_class.new(user_id: "user-123")
      new_context = context.with_attributes(plan: "pro", region: "us")

      expect(new_context["plan"]).to eq("pro")
      expect(new_context["region"]).to eq("us")
    end
  end

  describe "#merge" do
    it "merges another context" do
      context1 = described_class.new(user_id: "user-1", email: "a@test.com")
      context2 = described_class.new(user_id: "user-2", plan: "pro")

      merged = context1.merge(context2)

      expect(merged.user_id).to eq("user-2")
      expect(merged["email"]).to eq("a@test.com")
      expect(merged["plan"]).to eq("pro")
    end

    it "handles nil other context" do
      context = described_class.new(user_id: "user-1")
      merged = context.merge(nil)

      expect(merged).to eq(context)
    end

    it "preserves user_id from first context if second is nil" do
      context1 = described_class.new(user_id: "user-1")
      context2 = described_class.new(plan: "pro")

      merged = context1.merge(context2)

      expect(merged.user_id).to eq("user-1")
    end
  end

  describe "#strip_private_attributes" do
    it "removes attributes starting with underscore" do
      context = described_class.new(
        user_id: "user-123",
        email: "test@example.com",
        _secret: "hidden",
        _internal: "value"
      )

      stripped = context.strip_private_attributes

      expect(stripped.user_id).to eq("user-123")
      expect(stripped["email"]).to eq("test@example.com")
      expect(stripped["_secret"]).to be_nil
      expect(stripped["_internal"]).to be_nil
    end
  end

  describe "#empty?" do
    it "returns true for empty context" do
      expect(described_class.new.empty?).to be true
    end

    it "returns false when user_id is set" do
      expect(described_class.new(user_id: "user-123").empty?).to be false
    end

    it "returns false when attributes are set" do
      expect(described_class.new(foo: "bar").empty?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash representation for API" do
      context = described_class.new(user_id: "user-123", email: "test@example.com")
      hash = context.to_h

      expect(hash).to eq({
        "userId" => "user-123",
        "attributes" => { "email" => "test@example.com" }
      })
    end

    it "omits userId if nil" do
      context = described_class.new(email: "test@example.com")
      expect(context.to_h).not_to have_key("userId")
    end

    it "omits attributes if empty" do
      context = described_class.new(user_id: "user-123")
      expect(context.to_h).not_to have_key("attributes")
    end
  end

  describe ".from_hash" do
    it "creates a context from a hash" do
      context = described_class.from_hash({
        "userId" => "user-123",
        "attributes" => { "email" => "test@example.com" }
      })

      expect(context.user_id).to eq("user-123")
      expect(context["email"]).to eq("test@example.com")
    end

    it "handles nil input" do
      context = described_class.from_hash(nil)
      expect(context.empty?).to be true
    end
  end

  describe "#==" do
    it "returns true for equal contexts" do
      context1 = described_class.new(user_id: "user-123", email: "test@example.com")
      context2 = described_class.new(user_id: "user-123", email: "test@example.com")

      expect(context1).to eq(context2)
    end

    it "returns false for different contexts" do
      context1 = described_class.new(user_id: "user-123")
      context2 = described_class.new(user_id: "user-456")

      expect(context1).not_to eq(context2)
    end
  end
end
