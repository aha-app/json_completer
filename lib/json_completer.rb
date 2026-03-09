# frozen_string_literal: true

require 'set'
require 'stringio'

class JsonCompleter
  ParseError = Class.new(StandardError)

  STRUCTURE_CHARS = ['[', '{', ',', ':'].to_set.freeze
  KEYWORD_MAP = { 't' => 'true', 'f' => 'false', 'n' => 'null' }.freeze
  VALID_PRIMITIVES = %w[true false null].to_set.freeze

  ParsingState = Struct.new(
    :output_tokens, :context_stack, :last_index, :input_length, :incomplete_string_token,
    keyword_init: true
  ) do
    def initialize(
      output_tokens: [], context_stack: [], last_index: 0, input_length: 0, incomplete_string_token: nil
    )
      super
    end
  end

  ParseState = Struct.new(
    :root, :root_assigned, :context_stack, :last_index, :input_length, :token_state, :input_snapshot,
    keyword_init: true
  ) do
    def initialize(
      root: nil, root_assigned: false, context_stack: [], last_index: 0, input_length: 0, token_state: nil,
      input_snapshot: nil
    )
      super
    end
  end

  ParseSlot = Struct.new(:container, :key, :root, keyword_init: true)

  ObjectContext = Struct.new(:container, :mode, :current_key, keyword_init: true) do
    def initialize(container:, mode: :key_or_end, current_key: nil)
      super
    end
  end

  ArrayContext = Struct.new(:container, :mode, :provisional_index, keyword_init: true) do
    def initialize(container:, mode: :value_or_end, provisional_index: nil)
      super
    end
  end

  def self.complete(partial_json)
    new.complete(partial_json)
  end

  def self.parse(partial_json)
    new.parse(partial_json)
  end

  def self.new_state
    ParsingState.new
  end

  def self.new_parse_state
    ParseState.new
  end

  def initialize(state = self.class.new_state, parse_state = self.class.new_parse_state)
    @state = state
    @parse_state = parse_state
  end
end

require_relative 'json_completer/scanners'
require_relative 'json_completer/completion_engine'
require_relative 'json_completer/parser_engine'
