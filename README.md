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

## Architecture

The SDK is organized into clean, modular components:

```
flagkit/
├── flagkit.rb              # Main entry point and module methods
├── client.rb               # FlagKit::Client implementation
├── options.rb              # Configuration options
├── version.rb              # Version info
├── core/                   # Core components
│   ├── cache.rb            # In-memory cache with TTL
│   ├── context_manager.rb  # Context management
│   ├── polling_manager.rb  # Background polling
│   ├── event_queue.rb      # Event batching
│   └── event_persistence.rb # Crash-resilient persistence
├── http/                   # HTTP client, circuit breaker, retry
│   ├── http_client.rb
│   └── circuit_breaker.rb
├── error/                  # Error types and codes
│   ├── error.rb
│   ├── error_code.rb
│   └── sanitizer.rb        # Error message sanitization
├── types/                  # Type definitions
│   ├── evaluation_context.rb
│   ├── evaluation_result.rb
│   └── flag_state.rb
└── utils/                  # Utilities
    └── security.rb         # PII detection, HMAC signing
```

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
  local_port: nil                               # Local dev server port (uses http://localhost:{port}/api/v1)
)
```

## Local Development

For local development, use the `local_port` option to connect to a local FlagKit server:

```ruby
client = FlagKit.initialize(
  'sdk_your_api_key',
  local_port: 8200  # Uses http://localhost:8200/api/v1
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

## Security Features

### PII Detection

The SDK can detect and warn about potential PII (Personally Identifiable Information) in contexts and events:

```ruby
# Enable strict PII mode - raises errors instead of warnings
client = FlagKit.initialize(
  'sdk_...',
  strict_pii_mode: true
)

# Attributes containing PII will raise SecurityError
begin
  FlagKit.identify('user-123', email: 'user@example.com')  # PII detected!
rescue FlagKit::SecurityError => e
  puts "PII error: #{e.message}"
end

# Use private attributes to mark fields as intentionally containing PII
context = FlagKit::EvaluationContext.new(
  user_id: 'user-123',
  email: 'user@example.com',
  _email: true  # Underscore prefix marks as private
)
```

### Request Signing

POST requests to the FlagKit API are signed with HMAC-SHA256 for integrity:

```ruby
# Enabled by default, can be disabled if needed
client = FlagKit.initialize(
  'sdk_...',
  enable_request_signing: false  # Disable signing
)
```

### Bootstrap Signature Verification

Verify bootstrap data integrity using HMAC signatures:

```ruby
# Create signed bootstrap data
bootstrap = FlagKit::Security.create_bootstrap_signature(
  { 'feature-a' => true, 'feature-b' => 'value' },
  'sdk_your_api_key'
)

# Use signed bootstrap with verification
client = FlagKit.initialize(
  'sdk_...',
  bootstrap: bootstrap,
  bootstrap_verification_enabled: true,
  bootstrap_verification_max_age: 86_400_000,  # 24 hours in milliseconds
  bootstrap_verification_on_failure: 'error'   # 'warn' (default), 'error', or 'ignore'
)
```

### Cache Encryption

Enable AES-256-GCM encryption for cached flag data:

```ruby
client = FlagKit.initialize(
  'sdk_...',
  encrypt_cache: true
)
```

### Evaluation Jitter (Timing Attack Protection)

Add random delays to flag evaluations to prevent cache timing attacks:

```ruby
client = FlagKit.initialize(
  'sdk_...',
  evaluation_jitter_enabled: true,
  evaluation_jitter_min_ms: 5,
  evaluation_jitter_max_ms: 15
)
```

### Error Sanitization

Automatically redact sensitive information from error messages:

```ruby
client = FlagKit.initialize(
  'sdk_...',
  error_sanitization_enabled: true,
  error_sanitization_preserve_original: false  # Set true for debugging
)
# Errors will have paths, IPs, API keys, and emails redacted
```

## Event Persistence

Enable crash-resilient event persistence to prevent data loss:

```ruby
client = FlagKit.initialize(
  'sdk_...',
  persist_events: true,
  event_storage_path: '/path/to/storage',  # Optional, defaults to temp dir
  max_persisted_events: 10_000,            # Optional, default 10000
  persistence_flush_interval: 1000         # Optional, default 1000ms
)
```

Events are written to disk before being sent, and automatically recovered on restart.

## Key Rotation

Support seamless API key rotation:

```ruby
client = FlagKit.initialize(
  'sdk_primary_key',
  secondary_api_key: 'sdk_secondary_key',
  key_rotation_grace_period: 300  # 5 minutes
)
# SDK will automatically failover to secondary key on 401 errors
```

## All Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key` | String | Required | API key for authentication |
| `secondary_api_key` | String | nil | Secondary key for rotation |
| `key_rotation_grace_period` | Integer | 300 | Grace period in seconds |
| `polling_interval` | Integer | 30 | Polling interval in seconds |
| `cache_ttl` | Integer | 300 | Cache TTL in seconds |
| `max_cache_size` | Integer | 1000 | Maximum cache entries |
| `cache_enabled` | Boolean | true | Enable local caching |
| `encrypt_cache` | Boolean | false | Enable AES-256-GCM cache encryption |
| `events_enabled` | Boolean | true | Enable event tracking |
| `event_batch_size` | Integer | 10 | Events per batch |
| `event_flush_interval` | Integer | 30 | Seconds between flushes |
| `timeout` | Integer | 10 | Request timeout in seconds |
| `retry_attempts` | Integer | 3 | Number of retry attempts |
| `circuit_breaker_threshold` | Integer | 5 | Failures before circuit opens |
| `circuit_breaker_reset_timeout` | Integer | 30 | Seconds before half-open |
| `bootstrap` | Hash | nil | Initial flag values |
| `bootstrap_verification_enabled` | Boolean | true | Verify bootstrap signatures |
| `bootstrap_verification_max_age` | Integer | 86400000 | Max bootstrap age (ms) |
| `bootstrap_verification_on_failure` | String | 'warn' | Action on failure |
| `local_port` | Integer | nil | Local development port |
| `logger` | Object | nil | Custom logger |
| `storage` | Object | nil | Custom storage adapter |
| `strict_pii_mode` | Boolean | false | Error on PII detection |
| `enable_request_signing` | Boolean | true | Enable request signing |
| `persist_events` | Boolean | false | Enable event persistence |
| `event_storage_path` | String | temp dir | Event storage directory |
| `max_persisted_events` | Integer | 10000 | Max persisted events |
| `persistence_flush_interval` | Integer | 1000 | Persistence flush interval (ms) |
| `evaluation_jitter_enabled` | Boolean | false | Enable timing attack protection |
| `evaluation_jitter_min_ms` | Integer | 5 | Min jitter delay (ms) |
| `evaluation_jitter_max_ms` | Integer | 15 | Max jitter delay (ms) |
| `error_sanitization_enabled` | Boolean | true | Sanitize error messages |
| `error_sanitization_preserve_original` | Boolean | false | Keep original message |

## Thread Safety

All SDK methods are safe for concurrent use from multiple threads. The client uses internal synchronization (Mutex) to ensure thread-safe access to:

- Flag cache
- Event queue
- Context management
- Polling state

## License

MIT License - see [LICENSE](LICENSE) for details.
