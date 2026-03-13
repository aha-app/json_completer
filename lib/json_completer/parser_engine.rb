# frozen_string_literal: true

class JsonCompleter
  module ParserEngine
    def parse(partial_json)
      input = partial_json
      # The hot path works on raw bytes, not 1-character Ruby strings. JSON punctuation is ASCII,
      # so getbyte/bytesize let us compare cheap integers while multibyte UTF-8 payload stays intact.
      input_length = input.bytesize

      if @parse_state.nil? ||
         @parse_state.input_length > input_length ||
         (@parse_state.input_length < input_length && reset_parse_state_for_input_growth?(input))
        @parse_state = self.class.new_parse_state
      elsif @parse_state.input_length == input_length
        if @parse_state.input_snapshot == input
          finalize_parse_result
          return @parse_state.root
        end

        @parse_state = self.class.new_parse_state
      end

      return nil if input.empty?

      begin
        prepare_parse_state_for_incremental_input

        index = @parse_state.last_index
        while index < input_length
          if @parse_state.token_state
            index = continue_parse_token(input, index)
            next
          end

          byte = input.getbyte(index)
          if top_level_value_complete? && !whitespace_byte?(byte)
            raise ParseError, 'unexpected token after top-level value'
          end

          # ASCII byte values: 9/10/13/32 = whitespace, 34 = ", 44 = ,, 45 = -, 58 = :,
          # 91/93 = [] , 102/110/116 = f/n/t, 123/125 = {}.
          case byte
          when 9, 10, 13, 32
            index += 1
          when 34
            start_parse_string_token
            index += 1
          when 44
            parse_comma!
            index += 1
          when 45, 48..57
            start_parse_number_token(byte)
            index += 1
          when 58
            parse_colon!
            index += 1
          when 91
            start_parse_container([])
            index += 1
          when 93
            close_parse_array!
            index += 1
          when 102, 110, 116
            start_parse_keyword_token(byte)
            index += 1
          when 123
            start_parse_container({})
            index += 1
          when 125
            close_parse_object!
            index += 1
          else
            raise ParseError, "unexpected token #{input.byteslice(index, 1).inspect}"
          end
        end

        @parse_state.last_index = index
        @parse_state.input_length = input_length
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

    def start_parse_number_token(first_byte)
      slot = parse_value_slot!
      token = Scanners::NumberToken.new(slot: slot)
      token.append_byte(first_byte)
      assign_parse_slot(slot, token.parsed_value)
      transition_after_parse_value(slot)
      @parse_state.token_state = token
    end

    def continue_parse_number_token(input, index)
      token = @parse_state.token_state
      length = input.bytesize

      while index < length && token.append_byte(input.getbyte(index))
        assign_parse_slot(token.slot, token.parsed_value)
        index += 1
      end

      raise ParseError, 'invalid number literal' if token.invalid?

      @parse_state.token_state = nil if index < length
      index
    end

    def start_parse_keyword_token(first_byte)
      slot = parse_value_slot!
      token = Scanners::KeywordToken.new(slot: slot, target: keyword_target_for_byte(first_byte), matched: 1)
      assign_parse_slot(slot, token.parsed_value)
      transition_after_parse_value(slot)
      @parse_state.token_state = token
    end

    def continue_parse_keyword_token(input, index)
      token = @parse_state.token_state
      length = input.bytesize

      while index < length && token.matched < token.target.length && token.append_byte(input.getbyte(index))
        index += 1
      end

      raise ParseError, 'invalid keyword literal' if token.matched < token.target.length && index < length

      @parse_state.token_state = nil if index < length || token.matched == token.target.length
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

    def reset_parse_state_for_input_growth?(input)
      return false unless @parse_state.input_snapshot
      return false unless prefix_validation_required?

      !input.start_with?(@parse_state.input_snapshot)
    end

    def prefix_validation_required?
      @parse_state.context_stack.empty?
    end

    def keyword_target_for_byte(byte)
      case byte
      when 102
        'false'
      when 110
        'null'
      when 116
        'true'
      else
        raise ParseError, "unexpected keyword token byte: #{byte}"
      end
    end

    def whitespace_byte?(byte)
      case byte
      when 9, 10, 13, 32
        true
      else
        false
      end
    end
  end

  include ParserEngine
end
