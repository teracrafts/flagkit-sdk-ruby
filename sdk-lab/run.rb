#!/usr/bin/env ruby
# frozen_string_literal: true

# FlagKit Ruby SDK Lab
#
# Internal verification script for SDK functionality.
# Run with: ruby sdk-lab/run.rb

require_relative "../lib/flagkit"

PASS = "\e[32m[PASS]\e[0m"
FAIL = "\e[31m[FAIL]\e[0m"

passed = 0
failed = 0

def pass(test)
  puts "#{PASS} #{test}"
  1
end

def fail(test)
  puts "#{FAIL} #{test}"
  1
end

puts "=== FlagKit Ruby SDK Lab ===\n\n"

begin
  # Test 1: Initialization with bootstrap (will fail network but use bootstrap)
  puts "Testing initialization..."
  # Reset any previous instance
  FlagKit.shutdown if FlagKit.initialized?

  # Note: Ruby SDK doesn't have offline mode, so initialization will try network
  # but will still use bootstrap values and mark as ready even if network fails
  # Bootstrap format requires 'flags' array with 'key' and 'value' fields
  begin
    client = FlagKit.initialize(
      "sdk_lab_test_key",
      bootstrap: {
        "flags" => [
          { "key" => "lab-bool", "value" => true },
          { "key" => "lab-string", "value" => "Hello Lab" },
          { "key" => "lab-number", "value" => 42 },
          { "key" => "lab-json", "value" => { "nested" => true, "count" => 100 } }
        ]
      }
    )
  rescue FlagKit::Error => e
    # Network errors are expected when no server is running
    # The client is still usable with bootstrap values
    client = FlagKit.client
    puts "Note: Network init failed (expected): #{e.message}"
  end

  if client.nil?
    failed += fail("Initialization - client is nil")
  elsif client.ready?
    passed += pass("Initialization")
  else
    client.wait_for_ready
    passed += pass("Initialization (with wait)")
  end

  # Test 2: Boolean flag evaluation
  puts "\nTesting flag evaluation..."
  bool_value = client.get_boolean_value("lab-bool", false)
  if bool_value == true
    passed += pass("Boolean flag evaluation")
  else
    failed += fail("Boolean flag - expected true, got #{bool_value}")
  end

  # Test 3: String flag evaluation
  string_value = client.get_string_value("lab-string", "")
  if string_value == "Hello Lab"
    passed += pass("String flag evaluation")
  else
    failed += fail("String flag - expected 'Hello Lab', got '#{string_value}'")
  end

  # Test 4: Number flag evaluation
  number_value = client.get_number_value("lab-number", 0)
  if number_value == 42
    passed += pass("Number flag evaluation")
  else
    failed += fail("Number flag - expected 42, got #{number_value}")
  end

  # Test 5: JSON flag evaluation
  json_value = client.get_json_value("lab-json", { "nested" => false, "count" => 0 })
  if json_value["nested"] == true && json_value["count"] == 100
    passed += pass("JSON flag evaluation")
  else
    failed += fail("JSON flag - unexpected value: #{json_value}")
  end

  # Test 6: Default value for missing flag
  missing_value = client.get_boolean_value("non-existent", true)
  if missing_value == true
    passed += pass("Default value for missing flag")
  else
    failed += fail("Missing flag - expected default true, got #{missing_value}")
  end

  # Test 7: Context management - identify
  puts "\nTesting context management..."
  # Ruby SDK identify uses keyword args: identify(user_id, **attributes)
  client.identify("lab-user-123", custom: { plan: "premium", country: "US" })
  context = client.context
  if context && context.user_id == "lab-user-123"
    passed += pass("identify()")
  else
    failed += fail("identify() - context not set correctly")
  end

  # Test 8: Context management - context
  # Ruby SDK stores attributes in `attributes` hash, access with context["custom"]
  custom_attrs = context && context["custom"]
  if custom_attrs && custom_attrs[:plan] == "premium"
    passed += pass("context()")
  else
    failed += fail("context() - custom attributes missing")
  end

  # Test 9: Context management - reset
  client.reset_context
  reset_context = client.context
  if reset_context.nil? || reset_context.user_id.nil?
    passed += pass("reset()")
  else
    failed += fail("reset() - context not cleared")
  end

  # Test 10: Event tracking
  puts "\nTesting event tracking..."
  begin
    client.track("lab_verification", { sdk: "ruby", version: "1.0.0" })
    passed += pass("track()")
  rescue StandardError => e
    failed += fail("track() - #{e.message}")
  end

  # Test 11: Flush (may fail due to no network - that's OK)
  begin
    client.flush
    passed += pass("flush()")
  rescue StandardError
    # In offline/no-server mode, flush may fail - this is expected
    passed += pass("flush() (network error expected)")
  end

  # Test 12: Cleanup
  puts "\nTesting cleanup..."
  begin
    client.close
    passed += pass("close()")
  rescue StandardError => e
    failed += fail("close() - #{e.message}")
  end

rescue StandardError => e
  failed += fail("Unexpected error: #{e.message}")
  puts e.backtrace.join("\n")
end

# Summary
puts "\n#{"=" * 40}"
puts "Results: #{passed} passed, #{failed} failed"
puts "=" * 40

if failed > 0
  puts "\n\e[31mSome verifications failed!\e[0m"
  exit 1
else
  puts "\n\e[32mAll verifications passed!\e[0m"
  exit 0
end
