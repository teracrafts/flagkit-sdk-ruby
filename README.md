# FlagKit Ruby SDK

Official Ruby SDK for [FlagKit](https://flagkit.dev) feature flag management.

## Requirements

- Ruby 3.0+

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'flagkit'
```

Then execute:

```bash
bundle install
```

Or install directly:

```bash
gem install flagkit
```

## Quick Start

```ruby
require 'flagkit'

# Initialize the SDK
client = FlagKit.initialize('sdk_your_api_key')

# Identify the current user
FlagKit.identify('user-123', plan: 'pro')

# Evaluate feature flags
dark_mode = FlagKit.get_boolean_value('dark-mode', false)
theme = FlagKit.get_string_value('theme', 'light')
max_items = FlagKit.get_number_value('max-items', 10)
config = FlagKit.get_json_value('feature-config', {})

# Track events
FlagKit.track('button_clicked', button: 'signup')

# Shutdown when done
FlagKit.shutdown
```

## Features

- **Type-safe evaluation** - Boolean, string, number, and JSON flag types
- **Local caching** - Fast evaluations with configurable TTL and optional encryption
- **Background polling** - Automatic flag updates
- **Event tracking** - Analytics with batching and crash-resilient persistence
- **Resilient** - Circuit breaker, retry with exponential backoff, offline support
- **Thread-safe** - Safe for concurrent use
- **Security** - PII detection, request signing, bootstrap verification, timing attack protection

## Configuration Options

```ruby
client = FlagKit.initialize(
  'sdk_your_api_key',
  polling_interval: 30,                         # Seconds between polls
  cache_ttl: 300,                               # Cache time-to-live in seconds
  cache_enabled: true,                          # Enable/disable caching
  events_enabled: true,                         # Enable/disable event tracking
  event_batch_size: 10,                         # Events per batch
  event_flush_interval: 30,                     # Seconds between flushes
  timeout: 10,                                  # Request timeout in seconds
  retry_attempts: 3,                            # Number of retry attempts
  circuit_breaker_threshold: 5,                 # Failures before circuit opens
  circuit_breaker_reset_timeout: 30,            # Seconds before half-open
)
```

Security features such as PII detection, request signing, bootstrap verification, cache encryption, evaluation jitter, and error sanitization are also available as configuration options.

## Local Development


```ruby
client = FlagKit.initialize(
  'sdk_your_api_key',
)
```

## Using the Client Directly

```ruby
client = FlagKit::Client.new(
  FlagKit::Options.new(api_key: 'sdk_your_api_key')
)
client.initialize_sdk

# Wait for initialization
client.wait_for_ready(timeout: 5)

# Evaluate flags
result = client.evaluate('my-feature', false)
puts result.value
puts result.reason
puts result.version

# Clean up
client.close
```

## Evaluation Context

```ruby
# Build a context
context = FlagKit::EvaluationContext.new(
  user_id: 'user-123',
  email: 'user@example.com',
  plan: 'enterprise'
)

# Use with evaluation
value = FlagKit.get_boolean_value('premium-feature', false, context: context)

# Private attributes (stripped before sending to server)
context = FlagKit::EvaluationContext.new(
  user_id: 'user-123',
  _internal_id: 'hidden'  # Underscore prefix = private
)
```

## Error Handling

```ruby
begin
  FlagKit.initialize('invalid_key')
rescue FlagKit::Error => e
  puts "Error code: #{e.code}"
  puts "Message: #{e.message}"
  puts "Recoverable: #{e.recoverable?}"
end
```

## API Reference

### Module Methods

| Method | Description |
|--------|-------------|
| `FlagKit.initialize(api_key, **options)` | Initialize the SDK |
| `FlagKit.shutdown` | Shutdown and release resources |
| `FlagKit.initialized?` | Check if SDK is initialized |
| `FlagKit.identify(user_id, **attributes)` | Set user context |
| `FlagKit.reset_context` | Clear user context |
| `FlagKit.get_boolean_value(key, default, context:)` | Get boolean flag |
| `FlagKit.get_string_value(key, default, context:)` | Get string flag |
| `FlagKit.get_number_value(key, default, context:)` | Get number flag |
| `FlagKit.get_json_value(key, default, context:)` | Get JSON flag |
| `FlagKit.evaluate(key, default, context:)` | Get full evaluation result |
| `FlagKit.track(event_type, data)` | Track analytics event |

### Client Methods

| Method | Description |
|--------|-------------|
| `client.initialize_sdk` | Initialize and fetch flags |
| `client.wait_for_ready(timeout:)` | Wait for initialization |
| `client.ready?` | Check if ready |
| `client.identify(user_id, **attributes)` | Set user context |
| `client.reset_context` | Clear user context |
| `client.context` | Get current context |
| `client.evaluate(key, default, context:)` | Evaluate a flag |
| `client.get_boolean_value(key, default, context:)` | Get boolean value |
| `client.get_string_value(key, default, context:)` | Get string value |
| `client.get_number_value(key, default, context:)` | Get number value |
| `client.get_int_value(key, default, context:)` | Get integer value |
| `client.get_json_value(key, default, context:)` | Get JSON value |
| `client.track(event_type, data)` | Track an event |
| `client.close` | Close and release resources |

## Thread Safety

All SDK methods are safe for concurrent use from multiple threads. The client uses internal synchronization (Mutex) to ensure thread-safe access to:

- Flag cache
- Event queue
- Context management
- Polling state

## License

MIT License - see [LICENSE](LICENSE) for details.
