# frozen_string_literal: true

class JsonCompleter
  module ParserEngine
    def parse(partial_json)
      input = partial_json

      if @parse_state.nil? ||
         @parse_state.input_length > input.length ||
         (@parse_state.input_snapshot && !input.start_with?(@parse_state.input_snapshot))
        @parse_state = self.class.new_parse_state
      end

      return nil if input.empty?

      begin
        if @parse_state.input_length == input.length
          finalize_parse_result
          return @parse_state.root
        end

        prepare_parse_state_for_incremental_input

        index = @parse_state.last_index
        while index < input.length
          if @parse_state.token_state
            index = continue_parse_token(input, index)
            next
          end

          char = input[index]
          if top_level_value_complete? && char !~ /\s/
            raise ParseError, 'unexpected token after top-level value'
          end

          case char
          when /\s/
            index += 1
          when '{'
            start_parse_container({})
            index += 1
          when '['
            start_parse_container([])
            index += 1
          when '}'
            close_parse_object!
            index += 1
          when ']'
            close_parse_array!
            index += 1
          when '"'
            start_parse_string_token
            index += 1
          when ':'
            parse_colon!
            index += 1
          when ','
            parse_comma!
            index += 1
          when 't', 'f', 'n'
            start_parse_keyword_token(char)
            index += 1
          when '-', '0'..'9'
            start_parse_number_token(char)
            index += 1
          else
            raise ParseError, "unexpected token #{char.inspect}"
          end
        end

        @parse_state.last_index = index
        @parse_state.input_length = input.length
        @parse_state.input_snapshot = input
        finalize_parse_result
        @parse_state.root
      rescue ParseError
        @parse_state = self.class.new_parse_state
        raise
      end
    end

    private

    def prepare_parse_state_for_incremental_input
      token = @parse_state.token_state
      return unless token.is_a?(Scanners::ParsedStringToken) && token.role == :key && token.visible_key

      restore_visible_key_placeholder(token)
    end

    def continue_parse_token(input, index)
      token = @parse_state.token_state

      case token
      when Scanners::ParsedStringToken
        continue_parse_string_token(input, index)
      when Scanners::NumberToken
        continue_parse_number_token(input, index)
      when Scanners::KeywordToken
        continue_parse_keyword_token(input, index)
      else
        raise ParseError, "unsupported token state: #{token.class}"
      end
    end

    def start_parse_container(container)
      slot = parse_value_slot!
      assign_parse_slot(slot, container)
      transition_after_parse_value(slot)

      @parse_state.context_stack << if container.is_a?(Hash)
                                      ObjectContext.new(container: container)
                                    else
                                      ArrayContext.new(container: container)
                                    end
    end

    def close_parse_object!
      context = @parse_state.context_stack.last
      raise ParseError, 'unexpected object close' unless context.is_a?(ObjectContext)
      raise ParseError, 'cannot close object while a key is incomplete' if context.mode == :key_in_progress
      raise ParseError, 'cannot close object before a colon' if context.mode == :after_key
      raise ParseError, 'cannot close object while a value is missing' if context.mode == :value

      @parse_state.context_stack.pop
    end

    def close_parse_array!
      context = @parse_state.context_stack.last
      raise ParseError, 'unexpected array close' unless context.is_a?(ArrayContext)
      raise ParseError, 'cannot close array while a value is missing' if context.provisional_index

      @parse_state.context_stack.pop
    end

    def start_parse_string_token
      context = @parse_state.context_stack.last

      if context.is_a?(ObjectContext) && context.mode == :key_or_end
        context.mode = :key_in_progress
        @parse_state.token_state = Scanners::ParsedStringToken.new(role: :key, context: context)
        return
      end

      slot = parse_value_slot!
      token = Scanners::ParsedStringToken.new(role: :value, slot: slot)
      assign_parse_slot(slot, token.buffer)
      transition_after_parse_value(slot)
      @parse_state.token_state = token
    end

    def continue_parse_string_token(input, index)
      token = @parse_state.token_state
      index, status = Scanners.scan_string(input, index, token)
      raise ParseError, 'invalid string escape sequence' if status == :invalid_escape
      raise ParseError, 'invalid unicode escape sequence' if status == :invalid_unicode
      raise ParseError, 'invalid control character in string literal' if status == :invalid_control_character

      finish_parse_string_token! if status == :terminated
      index
    end

    def finish_parse_string_token!
      token = @parse_state.token_state
      return unless token

      if token.role == :key
        token.context.current_key = token.buffer.dup
        token.context.mode = :after_key
      end

      @parse_state.token_state = nil
    end

    def start_parse_number_token(first_char)
      slot = parse_value_slot!
      token = Scanners::NumberToken.new(slot: slot)
      token.append(first_char)
      assign_parse_slot(slot, token.parsed_value)
      transition_after_parse_value(slot)
      @parse_state.token_state = token
    end

    def continue_parse_number_token(input, index)
      token = @parse_state.token_state

      while index < input.length && token.append(input[index])
        assign_parse_slot(token.slot, token.parsed_value)
        index += 1
      end

      raise ParseError, 'invalid number literal' if token.invalid?

      @parse_state.token_state = nil if index < input.length
      index
    end

    def start_parse_keyword_token(first_char)
      slot = parse_value_slot!
      token = Scanners::KeywordToken.new(slot: slot, target: KEYWORD_MAP[first_char], matched: 1)
      assign_parse_slot(slot, token.parsed_value)
      transition_after_parse_value(slot)
      @parse_state.token_state = token
    end

    def continue_parse_keyword_token(input, index)
      token = @parse_state.token_state

      while index < input.length && token.matched < token.target.length && token.append(input[index])
        index += 1
      end

      raise ParseError, 'invalid keyword literal' if token.matched < token.target.length && index < input.length

      @parse_state.token_state = nil if index < input.length || token.matched == token.target.length
      index
    end

    def parse_colon!
      context = @parse_state.context_stack.last
      raise ParseError, 'unexpected colon' unless context.is_a?(ObjectContext) && context.mode == :after_key

      context.mode = :value
    end

    def parse_comma!
      context = @parse_state.context_stack.last
      raise ParseError, 'unexpected comma' unless context

      case context
      when ArrayContext
        raise ParseError, 'cannot add a comma while an array value is missing' unless context.mode == :after_value

        context.mode = :value_or_end
        context.provisional_index = context.container.length
      when ObjectContext
        raise ParseError, 'cannot add a comma while an object entry is incomplete' unless context.mode == :after_value

        context.mode = :key_or_end
        context.current_key = nil

      end
    end

    def parse_value_slot!
      context = @parse_state.context_stack.last

      unless context
        raise ParseError, 'unexpected token after top-level value' if @parse_state.root_assigned

        return ParseSlot.new(root: true)
      end

      case context
      when ArrayContext
        raise ParseError, 'expected comma before next array value' if context.mode == :after_value
        raise ParseError, 'cannot parse array value here' unless context.mode == :value_or_end

        index = context.provisional_index || context.container.length
        context.provisional_index = nil
        ParseSlot.new(container: context.container, key: index, root: false)
      when ObjectContext
        raise ParseError, 'expected colon before object value' if context.mode == :after_key
        raise ParseError, 'expected comma before next object entry' if context.mode == :after_value
        raise ParseError, 'expected object key' unless context.mode == :value

        ParseSlot.new(container: context.container, key: context.current_key, root: false)
      end
    end

    def top_level_value_complete?
      @parse_state.root_assigned &&
        @parse_state.context_stack.empty? &&
        @parse_state.token_state.nil?
    end

    def assign_parse_slot(slot, value)
      if slot.root
        @parse_state.root = value
        @parse_state.root_assigned = true
      else
        slot.container[slot.key] = value
      end
    end

    def transition_after_parse_value(slot)
      context = @parse_state.context_stack.last

      case context
      when ArrayContext
        context.mode = :after_value
      when ObjectContext
        context.mode = :after_value if slot.root || !context.current_key.nil?
      end
    end

    def finalize_parse_result
      token = @parse_state.token_state

      if token.is_a?(Scanners::ParsedStringToken) && token.role == :key
        update_visible_key_placeholder(token)
        return
      end

      @parse_state.context_stack.each do |context|
        case context
        when ObjectContext
          next unless %i[after_key value].include?(context.mode) && context.current_key

          context.container[context.current_key] = nil
        when ArrayContext
          next unless context.provisional_index

          context.container[context.provisional_index] = nil
        end
      end
    end

    def restore_visible_key_placeholder(token)
      if token.visible_key_replaced_present
        token.context.container[token.visible_key] = token.visible_key_replaced_value
      else
        token.context.container.delete(token.visible_key)
      end

      token.visible_key = nil
      token.visible_key_replaced_value = nil
      token.visible_key_replaced_present = false
    end

    def update_visible_key_placeholder(token)
      current_key = token.buffer.dup
      return if token.visible_key == current_key

      restore_visible_key_placeholder(token) if token.visible_key

      token.visible_key = current_key
      token.visible_key_replaced_present = token.context.container.key?(current_key)
      token.visible_key_replaced_value = token.context.container[current_key]
      token.context.container[current_key] = nil
    end
  end

  include ParserEngine
end
