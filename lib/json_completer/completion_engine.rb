# frozen_string_literal: true

class JsonCompleter
  module CompletionEngine
    def complete(partial_json)
      input = partial_json

      if @state.nil? || @state.input_length > input.length
        @state = ParsingState.new
      end

      return input if input.empty?
      return input if valid_json_primitive_or_document?(input)

      if @state.input_length == input.length && !@state.output_tokens.empty?
        return finalize_completion(@state.output_tokens.dup, @state.context_stack.dup, @state.incomplete_string_token)
      end

      output_tokens = @state.output_tokens.dup
      context_stack = @state.context_stack.dup
      index = @state.last_index
      length = input.length
      incomplete_string_token = @state.incomplete_string_token

      if incomplete_string_token
        output_tokens.pop if output_tokens.last&.start_with?('"') && output_tokens.last.end_with?('"')
      end

      while index < length
        if incomplete_string_token && index == @state.last_index
          index, status = Scanners.scan_string(input, index, incomplete_string_token)

          if status == :terminated || status == :invalid_unicode
            output_tokens << incomplete_string_token.buffer.string
            incomplete_string_token = nil
          else
            break
          end

          next
        end

        char = input[index]
        last_significant_char_in_output = get_last_significant_char(output_tokens)

        case char
        when '{'
          ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
          ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)
          output_tokens << char
          context_stack << '{'
          index += 1
        when '['
          ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
          ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)
          output_tokens << char
          context_stack << '['
          index += 1
        when '}'
          remove_trailing_comma(output_tokens)
          output_tokens << char
          context_stack.pop if !context_stack.empty? && context_stack.last == '{'
          index += 1
        when ']'
          output_tokens << char
          context_stack.pop if !context_stack.empty? && context_stack.last == '['
          index += 1
        when '"'
          ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
          ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

          string_token = Scanners::CompletionStringToken.new
          index, status = Scanners.scan_string(input, index + 1, string_token)

          if status == :terminated || status == :invalid_unicode
            output_tokens << string_token.buffer.string
          else
            incomplete_string_token = string_token
          end
        when ':'
          remove_trailing_comma(output_tokens) if last_significant_char_in_output == ','
          output_tokens << char
          index += 1
        when ','
          remove_trailing_comma(output_tokens)
          output_tokens << char
          index += 1
        when 't', 'f', 'n'
          ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
          ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

          keyword_val, consumed = Scanners.scan_keyword_literal(input, index, KEYWORD_MAP[char.downcase])
          output_tokens << keyword_val
          index += consumed
        when '-', '0'..'9'
          ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
          ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

          num_str, consumed = Scanners.scan_number_literal(input, index)
          output_tokens << num_str
          index += consumed
        when /\s/
          output_tokens << char
          index += 1
        else
          index += 1
        end
      end

      @state = ParsingState.new(
        output_tokens: output_tokens,
        context_stack: context_stack,
        last_index: index,
        input_length: length,
        incomplete_string_token: incomplete_string_token
      )

      finalize_completion(output_tokens.dup, context_stack.dup, incomplete_string_token)
    end

    private

    def finalize_completion(output_tokens, context_stack, incomplete_string_token = nil)
      output_tokens << incomplete_string_token.finalized_incomplete_value if incomplete_string_token

      last_sig_char_final = get_last_significant_char(output_tokens)

      unless context_stack.empty?
        current_ctx = context_stack.last
        if current_ctx == '{'
          if last_sig_char_final == '"'
            prev_sig_char = get_previous_significant_char(output_tokens)
            output_tokens << ':' << 'null' if ['{', ','].include?(prev_sig_char)
          elsif last_sig_char_final == ':'
            output_tokens << 'null'
          end
        elsif current_ctx == '['
          output_tokens << 'null' if last_sig_char_final == ','
        end
      end

      until context_stack.empty?
        opener = context_stack.pop
        remove_trailing_comma(output_tokens)
        output_tokens << (opener == '{' ? '}' : ']')
      end

      reassembled_json = output_tokens.join
      return 'null' if reassembled_json.match?(/\A\s*[,:]\s*\z/)

      reassembled_json
    end

    def get_last_significant_char(output_tokens)
      (output_tokens.length - 1).downto(0) do |index|
        stripped_token = output_tokens[index].strip
        return stripped_token[-1] unless stripped_token.empty?
      end

      nil
    end

    def get_previous_significant_char(output_tokens)
      significant_chars = []

      (output_tokens.length - 1).downto(0) do |index|
        stripped_token = output_tokens[index].strip
        next if stripped_token.empty?

        significant_chars << stripped_token[-1]
        return significant_chars[1] if significant_chars.length >= 2
      end

      nil
    end

    def ensure_comma_before_new_item(output_tokens, context_stack, last_sig_char)
      return if output_tokens.empty? || context_stack.empty? || last_sig_char.nil?
      return if STRUCTURE_CHARS.include?(last_sig_char)
      return unless context_stack.last == '[' || (context_stack.last == '{' && last_sig_char != ':')

      output_tokens << ','
    end

    def ensure_colon_if_value_expected(output_tokens, context_stack, last_sig_char)
      return if output_tokens.empty? || context_stack.empty? || last_sig_char.nil?
      return unless context_stack.last == '{' && last_sig_char == '"'

      output_tokens << ':'
    end

    def remove_trailing_comma(output_tokens)
      last_token_idx = -1

      (output_tokens.length - 1).downto(0) do |index|
        next if output_tokens[index].strip.empty?

        last_token_idx = index
        break
      end

      return unless last_token_idx != -1 && output_tokens[last_token_idx].strip == ','

      output_tokens.slice!(last_token_idx)

      while last_token_idx.positive? && output_tokens[last_token_idx - 1].strip.empty?
        output_tokens.slice!(last_token_idx - 1)
        last_token_idx -= 1
      end
    end

    def valid_json_primitive_or_document?(str)
      return true if VALID_PRIMITIVES.include?(str)

      if str.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/) &&
         !str.end_with?('.') && !str.match?(/[eE][+-]?$/)
        return true
      end

      str.match?(/\A"(?:[^"\\]|\\.)*"\z/)
    end
  end

  include CompletionEngine
end
