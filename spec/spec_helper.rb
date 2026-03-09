# frozen_string_literal: true

require 'json'
require 'json_completer'

module JsonCompleterSpecHelpers
  def expect_parse_to_match_json(input)
    expect(JsonCompleter.parse(input)).to eq(JSON.parse(input))
  end

  def expect_incremental_parse_result(completer, input, expected)
    expect(completer.parse(input)).to eq(expected)
  end

  def snapshot(value)
    Marshal.load(Marshal.dump(value))
  end
end

RSpec.configure do |config|
  config.include JsonCompleterSpecHelpers
end
