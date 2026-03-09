# JsonCompleter

A Ruby gem for incremental parsing of partial and incomplete JSON streams. It is built for streaming output from LLM providers such as OpenAI and Anthropic, and processes each new chunk in O(n) time by maintaining parser state between calls. Use `.parse` for parsed Ruby values and `.complete` when you specifically need completed JSON text.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'json_completer'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install json_completer
```

## Usage

### Basic Usage

Use `.parse` when you want the current parsed Ruby value directly from a partial stream:

```ruby
require 'json_completer'

# Parse partial JSON into Ruby objects
JsonCompleter.parse('{"name": "John", "age":')
# => {"name" => "John", "age" => nil}

# Handle incomplete strings
JsonCompleter.parse('{"message": "Hello wo')
# => {"message" => "Hello wo"}

# Close unclosed structures
JsonCompleter.parse('[1, 2, {"key": "value"')
# => [1, 2, {"key" => "value"}]
```

### Incremental Processing

For streaming scenarios where JSON arrives in chunks. Each call processes only new data (O(n) complexity) by maintaining parsing state:

```ruby
completer = JsonCompleter.new

# Process first chunk
result1 = completer.parse('{"users": [{"name": "')
# => {"users" => [{"name" => ""}]}

# Process additional data
result2 = completer.parse('{"users": [{"name": "Alice"}')
# => {"users" => [{"name" => "Alice"}]}

# Final parsed value
result3 = completer.parse('{"users": [{"name": "Alice"}, {"name": "Bob"}]}')
# => {"users" => [{"name" => "Alice"}, {"name" => "Bob"}]}
```

### String Output with `.complete`

Use `.complete` when you specifically need completed JSON text instead of parsed Ruby objects:

```ruby
JsonCompleter.complete('{"name": "John", "age":')
# => '{"name": "John", "age": null}'

JsonCompleter.complete('[1, 2, {"key": "value"')
# => '[1, 2, {"key": "value"}]'
```

This is the second-tier option when another layer expects JSON text and you want `json_completer` to materialize the current partial state as valid JSON.

#### Performance Characteristics

- **Zero reprocessing**: Maintains parsing state to avoid reparsing previously processed data
- **Linear complexity**: Each chunk processed in O(n) time where n = new data size, not total size
- **Memory efficient**: Uses token-based accumulation with minimal state overhead
- **Context preservation**: Tracks nested structures without full document analysis

### Common Use Cases

- **LLM streaming output**: Parse partial JSON emitted token-by-token from providers such as OpenAI and Anthropic
- **Incremental structured output parsing**: Keep a live Ruby object while more JSON arrives
- **JSON text completion**: Produce valid JSON text snapshots for downstream consumers that require a string

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Make your changes and add tests
4. Run the test suite (`bundle exec rspec`)
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a new Pull Request

## License

This gem is available as open source under the terms of the [MIT License](LICENSE).
