# frozen_string_literal: true

require 'stringio'

# JsonCompleter attempts to turn partial JSON strings into valid JSON.
# It handles incomplete primitives, missing values, and unclosed structures.
class JsonCompleter
  STRUCTURE_CHARS = ['[', '{', ',', ':'].to_set.freeze
  KEYWORD_MAP = { 't' => 'true', 'f' => 'false', 'n' => 'null' }.freeze
  VALID_PRIMITIVES = %w[true false null].to_set.freeze

  # Parsing state for incremental processing
  ParsingState = Struct.new(
    :output_tokens, :context_stack, :last_index, :input_length,
    :incomplete_string_start, :incomplete_string_buffer,
    :incomplete_string_escape_state, keyword_init: true
  ) do
    def initialize(
      output_tokens: [], context_stack: [], last_index: 0, input_length: 0,
      incomplete_string_start: nil, incomplete_string_buffer: nil,
      incomplete_string_escape_state: nil
    )
      super
    end
  end

  def self.complete(partial_json)
    new.complete(partial_json)
  end

  # Creates a new parsing state for incremental processing
  def self.new_state
    ParsingState.new
  end

  def initialize(state = self.class.new_state)
    @state = state
  end

  # Incrementally completes JSON using previous parsing state to avoid reprocessing.
  #
  # @param partial_json [String] The current partial JSON string (full accumulated input).
  # @return [String] Completed JSON.
  def complete(partial_json)
    input = partial_json

    # Initialize or reuse state
    if @state.nil? || @state.input_length > input.length
      # Fresh start or input was truncated - start over
      @state = ParsingState.new
    end

    return input if input.empty?
    return input if valid_json_primitive_or_document?(input)

    # If input hasn't grown since last time, just return completed version of existing state
    if @state.input_length == input.length && !@state.output_tokens.empty?
      return finalize_completion(@state.output_tokens.dup, @state.context_stack.dup)
    end

    # Handle incomplete string from previous state
    output_tokens = @state.output_tokens.dup
    context_stack = @state.context_stack.dup
    index = @state.last_index
    length = input.length
    incomplete_string_start = nil
    incomplete_string_buffer = nil
    incomplete_string_escape_state = nil

    # If we had an incomplete string, continue from where we left off
    if @state.incomplete_string_start
      incomplete_string_start = @state.incomplete_string_start
      incomplete_string_buffer = @state.incomplete_string_buffer || StringIO.new('"')
      incomplete_string_escape_state = @state.incomplete_string_escape_state
      # Remove the auto-completed string from output_tokens since we'll add the real one
      output_tokens.pop if output_tokens.last&.start_with?('"') && output_tokens.last.end_with?('"')
    end

    # Process from the current index
    while index < length
      # Special case: continuing an incomplete string
      if incomplete_string_buffer && index == @state.last_index
        str_value, new_index, terminated, new_buffer, new_escape_state = continue_parsing_string(
          input, incomplete_string_buffer, incomplete_string_escape_state
        )
        if terminated
          output_tokens << str_value
          incomplete_string_start = nil
          incomplete_string_buffer = nil
          incomplete_string_escape_state = nil
          # Continue processing from where string ended
          index = new_index
        else
          # String still incomplete, save state
          incomplete_string_buffer = new_buffer
          incomplete_string_escape_state = new_escape_state
          # We've consumed everything
          index = length
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
        # Do not repair missing object values - preserve invalid JSON
        remove_trailing_comma(output_tokens)
        output_tokens << char
        context_stack.pop if !context_stack.empty? && context_stack.last == '{'
        index += 1
      when ']'
        # Do not repair trailing commas in arrays - preserve invalid JSON
        output_tokens << char
        context_stack.pop if !context_stack.empty? && context_stack.last == '['
        index += 1
      when '"' # Start of a string (key or value)
        # Start of a new string (incomplete strings are handled at the top of the loop)
        ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
        ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

        string_start_index = index
        str_value, consumed, terminated, new_buffer, new_escape_state = parse_string_with_state(input, index)

        if terminated
          output_tokens << str_value
          incomplete_string_start = nil
          incomplete_string_buffer = nil
          incomplete_string_escape_state = nil
        else
          # String incomplete, save state for next call
          # Don't add to output_tokens yet - will be added during finalization
          incomplete_string_start = string_start_index
          incomplete_string_buffer = new_buffer
          incomplete_string_escape_state = new_escape_state
        end
        index += consumed
      when ':'
        # If the char before ':' was a comma, it's likely {"a":1, :"b":2} which is invalid.
        # Or if it was an opening brace/bracket.
        # Standard JSON doesn't allow this, but we aim to fix.
        # A colon should typically follow a string key.
        # If last char in output was a comma, remove it.
        remove_trailing_comma(output_tokens) if last_significant_char_in_output == ','
        output_tokens << char
        index += 1
      when ','
        # Handle cases like `[,` or `{,` or `,,` but do NOT repair `{"key":,` (missing object values)
        # if last_significant_char_in_output && STRUCTURE_CHARS.include?(last_significant_char_in_output) && last_significant_char_in_output != ':'
        #   output_tokens << 'null'
        # end
        remove_trailing_comma(output_tokens) # Avoid double commas
        output_tokens << char
        index += 1
      when 't', 'f', 'n' # true, false, null
        ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
        ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

        keyword_val, consumed = consume_and_complete_keyword(input, index, KEYWORD_MAP[char.downcase])
        output_tokens << keyword_val
        index += consumed
      when '-', '0'..'9' # Number
        ensure_comma_before_new_item(output_tokens, context_stack, last_significant_char_in_output)
        ensure_colon_if_value_expected(output_tokens, context_stack, last_significant_char_in_output)

        num_str, consumed = parse_number(input, index)
        output_tokens << num_str
        index += consumed
      when /\s/ # Whitespace
        # Preserve whitespace as-is
        output_tokens << char
        index += 1
      else # Unknown characters
        # For now, skip unknown characters as they are not part of JSON structure.
        # More advanced handling could try to wrap them in strings if contextually appropriate.
        index += 1
      end
    end

    # Update state
    updated_state = ParsingState.new(
      output_tokens: output_tokens,
      context_stack: context_stack,
      last_index: index,
      input_length: length,
      incomplete_string_start: incomplete_string_start,
      incomplete_string_buffer: incomplete_string_buffer,
      incomplete_string_escape_state: incomplete_string_escape_state
    )

    # Return completed JSON and updated state
    completed_json = finalize_completion(output_tokens.dup, context_stack.dup, incomplete_string_buffer)
    @state = updated_state

    completed_json
  end

  private

  # Finalizes the completion by handling post-processing and cleanup
  def finalize_completion(output_tokens, context_stack, incomplete_string_buffer = nil)
    # If we have an incomplete string buffer, add it with closing quote
    if incomplete_string_buffer
      buffer_str = incomplete_string_buffer.string
      # Remove incomplete escape sequences at the end

      # Count consecutive trailing backslashes
      trailing_backslashes = 0
      idx = buffer_str.length - 1
      while idx >= 0 && buffer_str[idx] == '\\'
        trailing_backslashes += 1
        idx -= 1
      end

      # If odd number of trailing backslashes, remove the last one (incomplete escape)
      # If even number, they're all paired as escaped backslashes, don't remove any
      buffer_str = buffer_str[0...-1] if trailing_backslashes.odd?

      # Check for incomplete unicode escape after handling backslashes
      if buffer_str =~ /\\u[0-9a-fA-F]{0,3}\z/ # Incomplete unicode
        buffer_str = buffer_str.sub(/\\u[0-9a-fA-F]{0,3}\z/, '')
      end

      # Always add closing quote for incomplete strings
      # (incomplete_string_buffer only exists when string wasn't terminated)
      buffer_str += '"'
      output_tokens << buffer_str
    end

    # Post-loop cleanup and final completions
    last_sig_char_final = get_last_significant_char(output_tokens)

    # If the last significant character suggests an incomplete structure:
    unless context_stack.empty?
      current_ctx = context_stack.last
      if current_ctx == '{' # Inside an object
        if last_sig_char_final == '"' # Just a key, e.g., {"key"
          # Check if this is a key (not a value) by looking at the context
          # If the previous significant character before this string was '{' or ',', it's a key
          prev_sig_char = get_previous_significant_char(output_tokens)
          output_tokens << ':' << 'null' if ['{', ','].include?(prev_sig_char)
        elsif last_sig_char_final == ':' # Key with colon, e.g., {"key":
          output_tokens << 'null'
        end
      elsif current_ctx == '[' # Inside an array
        output_tokens << 'null' if last_sig_char_final == ',' # Value then comma, e.g., [1,
      end
    end

    # Close any remaining open structures
    until context_stack.empty?
      opener = context_stack.pop
      remove_trailing_comma(output_tokens) # Clean up before closing
      output_tokens << (opener == '{' ? '}' : ']')
    end

    # Join tokens. A simple join might not be ideal for formatting.
    # A more sophisticated join would handle spaces around colons/commas.
    # For basic validity, this should be okay.
    reassembled_json = output_tokens.join

    # Final check: if the reassembled JSON is just a standalone comma or colon, it's invalid.
    # Return something more sensible like "null" or empty string.
    return 'null' if reassembled_json.match?(/\A\s*[,:]\s*\z/)

    reassembled_json
  end

  # Parses a new JSON string and returns parsing state for incremental processing
  # Returns [string_value, consumed_characters, was_terminated, buffer, escape_state]
  def parse_string_with_state(input, index)
    start_index = index
    output_str = StringIO.new
    # Initial quote
    output_str << input[index]
    index += 1
    terminated = false
    escape_state = nil

    while index < input.length
      char = input[index]

      if escape_state == :backslash
        # We're in an escape sequence
        if char == 'u'
          escape_state = { type: :unicode, hex: String.new }
          output_str << 'u' # Don't double the backslash
          index += 1
        else
          # Regular escape sequence
          output_str << char
          index += 1
          escape_state = nil
        end
      elsif escape_state.is_a?(Hash) && escape_state[:type] == :unicode
        # Collecting unicode hex digits
        if char.match?(/[0-9a-fA-F]/)
          escape_state[:hex] << char
          output_str << char
          index += 1
          if escape_state[:hex].length == 4
            # Unicode escape complete
            escape_state = nil
          end
        else
          # Invalid unicode escape - don't include it and close string
          # Remove the incomplete unicode escape
          str_so_far = output_str.string
          if str_so_far =~ /\\u[0-9a-fA-F]*\z/
            str_so_far = str_so_far.sub(/\\u[0-9a-fA-F]*\z/, '')
            output_str = StringIO.new(str_so_far)
          end
          output_str << '"'
          return [output_str.string, index - start_index, false, nil, nil]
        end
      elsif char == '\\'
        output_str << char
        escape_state = :backslash
        index += 1
      elsif char == '"'
        output_str << char
        terminated = true
        index += 1
        break
      else
        output_str << char
        index += 1
      end
    end

    if terminated
      [output_str.string, index - start_index, true, nil, nil]
    else
      # String incomplete - DON'T add closing quote here, it will be added during finalization
      [output_str.string, index - start_index, false, output_str, escape_state]
    end
  end

  # Continues parsing an incomplete string from saved state
  # Returns [string_value, new_index, was_terminated, buffer, escape_state]
  def continue_parsing_string(input, buffer, escape_state)
    # Buffer should not have closing quote - we removed it from parse_string_with_state

    index = @state.last_index
    terminated = false

    while index < input.length
      char = input[index]

      if escape_state == :backslash
        # We're in an escape sequence
        if char == 'u'
          escape_state = { type: :unicode, hex: String.new }
          buffer << 'u' # Don't double the backslash
          index += 1
        else
          # Regular escape sequence
          buffer << char
          index += 1
          escape_state = nil
        end
      elsif escape_state.is_a?(Hash) && escape_state[:type] == :unicode
        # Collecting unicode hex digits
        if char.match?(/[0-9a-fA-F]/)
          escape_state[:hex] << char
          buffer << char
          index += 1
          if escape_state[:hex].length == 4
            # Unicode escape complete
            escape_state = nil
          end
        else
          # Invalid unicode escape - don't include it and close string
          # Remove the incomplete unicode escape
          str_so_far = buffer.string
          if str_so_far =~ /\\u[0-9a-fA-F]*\z/
            str_so_far = str_so_far.sub(/\\u[0-9a-fA-F]*\z/, '')
            buffer = StringIO.new(str_so_far)
          end
          buffer << '"'
          return [buffer.string, index, false, nil, nil]
        end
      elsif char == '\\'
        buffer << char
        escape_state = :backslash
        index += 1
      elsif char == '"'
        buffer << char
        terminated = true
        index += 1
        break
      else
        buffer << char
        index += 1
      end
    end

    if terminated
      [buffer.string, index, true, nil, nil]
    else
      # String still incomplete - DON'T add quote here
      [buffer.string, index, false, buffer, escape_state]
    end
  end

  # Parses a JSON string starting at the given index.
  # Handles unterminated strings by closing them.
  # Returns [string_value, consumed_characters, was_terminated]
  def parse_string_with_termination_info(input, index)
    start_index = index
    output_str = StringIO.new
    output_str << input[index] # Initial quote
    index += 1
    terminated = false

    while index < input.length
      char = input[index]

      if char == '\\' && index + 1 < input.length
        next_char = input[index + 1]
        if next_char == 'u'
          # Handle unicode escape sequence
          index += 2 # Skip '\u'
          hex_digits = String.new

          # Collect up to 4 hex digits
          while hex_digits.length < 4 && index < input.length && input[index].match?(/[0-9a-fA-F]/)
            hex_digits << input[index]
            index += 1
          end

          if hex_digits.length == 4
            # Complete unicode escape
            output_str << '\\u' << hex_digits
          else
            # Incomplete unicode escape - remove it entirely and close string
            output_str << '"'
            return [output_str.string, index - start_index, false]
          end
        else
          # Regular escape sequence
          output_str << char << next_char
          index += 2
        end
      elsif char == '"'
        output_str << char
        terminated = true
        index += 1
        break
      else
        output_str << char
        index += 1
      end
    end

    output_str << '"' unless terminated # Close if unterminated
    [output_str.string, index - start_index, terminated]
  end

  # Parses a JSON string starting at the given index.
  # Handles unterminated strings by closing them.
  def parse_string(input, index)
    start_index = index
    output_str = StringIO.new
    output_str << input[index] # Initial quote
    index += 1
    terminated = false

    while index < input.length
      char = input[index]

      if char == '\\' && index + 1 < input.length
        next_char = input[index + 1]
        if next_char == 'u'
          # Handle unicode escape sequence
          index += 2 # Skip '\u'
          hex_digits = String.new

          # Collect up to 4 hex digits
          while hex_digits.length < 4 && index < input.length && input[index].match?(/[0-9a-fA-F]/)
            hex_digits << input[index]
            index += 1
          end

          if hex_digits.length == 4
            # Complete unicode escape
            output_str << '\\u' << hex_digits
          else
            # Incomplete unicode escape - remove it entirely and close string
            output_str << '"'
            return [output_str.string, index - start_index]
          end
        else
          # Regular escape sequence
          output_str << char << next_char
          index += 2
        end
      elsif char == '"'
        output_str << char
        terminated = true
        index += 1
        break
      else
        output_str << char
        index += 1
      end
    end

    output_str << '"' unless terminated # Close if unterminated
    [output_str.string, index - start_index]
  end

  # Parses a JSON number starting at the given index.
  # Completes numbers like "1." to "1.0".
  def parse_number(input, index)
    start_index = index
    num_str = StringIO.new

    # Optional leading minus
    if input[index] == '-'
      num_str << input[index]
      index += 1
    end

    # Integer part
    digits_before_dot = false
    while index < input.length && input[index] >= '0' && input[index] <= '9'
      num_str << input[index]
      index += 1
      digits_before_dot = true
    end

    # Decimal part
    has_dot = false
    if index < input.length && input[index] == '.'
      has_dot = true
      num_str << input[index]
      index += 1
      digits_after_dot = false
      while index < input.length && input[index] >= '0' && input[index] <= '9'
        num_str << input[index]
        index += 1
        digits_after_dot = true
      end
      num_str << '0' unless digits_after_dot # Append '0' if it's just "X." or "."
    end

    # If it was just "." or "-."
    current_val = num_str.string
    if current_val == '.'
      num_str = StringIO.new # Reset
      num_str << '0.0'
    elsif current_val == '-.'
      num_str = StringIO.new # Reset
      num_str << '-0.0'
    elsif current_val == '-' # Only a minus sign
      num_str = StringIO.new # Reset
      num_str << '0' # Or -0, but JSON standard usually serializes -0 as 0
    elsif !digits_before_dot && has_dot # e.g. ".5" -> "0.5"
      val = num_str.string
      num_str = StringIO.new
      num_str << '0' << val
    end

    # Exponent part
    if index < input.length && (input[index].downcase == 'e')
      # Check if there was a number before 'e'
      temp_num_val = num_str.string
      if temp_num_val.empty? || temp_num_val == '-' || temp_num_val == '.' || temp_num_val == '-.'
        # Invalid start for exponent, stop number parsing here
        return [
          if temp_num_val == '-'
            '0'
          else
            (temp_num_val.include?('.') ? temp_num_val + '0' : temp_num_val)
          end,
          index - start_index
        ]
      end

      num_str << input[index] # 'e' or 'E'
      index += 1
      if index < input.length && ['+', '-'].include?(input[index])
        num_str << input[index]
        index += 1
      end
      exponent_digits = false
      while index < input.length && input[index] >= '0' && input[index] <= '9'
        num_str << input[index]
        index += 1
        exponent_digits = true
      end
      # If 'e' was added but no digits followed, it's incomplete.
      # JSON requires digits after 'e'. We might strip 'e' or add '0'.
      # For robustness, let's add '0' if exponent is present but lacks digits.
      num_str << '0' unless exponent_digits
    end

    final_num_str = num_str.string
    # If the number is empty (e.g. bad start) or just "-", default to "0"
    return ['0', index - start_index] if final_num_str.empty? || final_num_str == '-'

    [final_num_str, index - start_index]
  end

  # Consumes characters from input that match the start of a keyword (true, false, null)
  # and returns the completed keyword and number of characters consumed.
  def consume_and_complete_keyword(input, index, target_keyword)
    consumed_count = 0
    (0...target_keyword.length).each do |k_idx|
      break if index + k_idx >= input.length

      break unless input[index + k_idx].downcase == target_keyword[k_idx]

      consumed_count += 1

      # Mismatch
    end
    # If at least the first char matched, we complete to the target_keyword
    return [target_keyword, consumed_count] if consumed_count.positive?

    # Fallback (should not be reached if called correctly, i.e., input[index] is t,f, or n)
    # This indicates the char was not the start of the expected keyword.
    # This case should be handled by the main loop's "else" (skip unknown char).
    # For safety, if it's called, treat the single char as a token to be skipped later.
    [input[index], 1]
  end

  # Gets the last non-whitespace character from the output tokens array.
  def get_last_significant_char(output_tokens)
    (output_tokens.length - 1).downto(0) do |i|
      token = output_tokens[i]
      stripped_token = token.strip
      return stripped_token[-1] unless stripped_token.empty?
    end
    nil
  end

  # Gets the second-to-last non-whitespace character from the output tokens array.
  def get_previous_significant_char(output_tokens)
    significant_chars = []
    (output_tokens.length - 1).downto(0) do |i|
      token = output_tokens[i]
      stripped_token = token.strip
      unless stripped_token.empty?
        significant_chars << stripped_token[-1]
        return significant_chars[1] if significant_chars.length >= 2
      end
    end
    nil
  end

  # Ensures a comma is added if needed before a new item in an array or object.
  def ensure_comma_before_new_item(output_tokens, context_stack, last_sig_char)
    return if output_tokens.empty? || context_stack.empty? || last_sig_char.nil?

    # No comma needed right after an opener, a colon, or another comma.
    return if STRUCTURE_CHARS.include?(last_sig_char)

    # If last_sig_char indicates a completed value/key:
    # (e.g., string quote, true/false/null end, number, or closing bracket/brace)
    # Add a comma if we are in an array or object.
    return unless context_stack.last == '[' || (context_stack.last == '{' && last_sig_char != ':')

    output_tokens << ','
  end

  # Ensures a colon is added if a value is expected after a key in an object.
  def ensure_colon_if_value_expected(output_tokens, context_stack, last_sig_char)
    return if output_tokens.empty? || context_stack.empty? || last_sig_char.nil?

    return unless context_stack.last == '{' && last_sig_char == '"' # In object, and last thing was a key (string)

    output_tokens << ':'
  end

  # Removes a trailing comma from the output_tokens if present.
  def remove_trailing_comma(output_tokens)
    last_token_idx = -1
    (output_tokens.length - 1).downto(0) do |i|
      unless output_tokens[i].strip.empty?
        last_token_idx = i
        break
      end
    end

    return unless last_token_idx != -1 && output_tokens[last_token_idx].strip == ','

    output_tokens.slice!(last_token_idx)
    # Also remove any whitespace tokens that were before this comma and are now effectively trailing
    while last_token_idx.positive? && output_tokens[last_token_idx - 1].strip.empty?
      output_tokens.slice!(last_token_idx - 1)
      last_token_idx -= 1
    end
  end

  # Checks if a string is a valid JSON primitive or a complete JSON document.
  # This is a helper for early exit if input is already fine.
  def valid_json_primitive_or_document?(str)
    # Check for simple primitives first
    return true if VALID_PRIMITIVES.include?(str)
    # Check for valid number (simplified regex, full JSON number is complex)
    # Allows integers, floats, but not ending with '.' or 'e'/'E' without digits
    if str.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/) &&
       !str.end_with?('.') && !str.match?(/[eE][+-]?$/)
      return true
    end
    # Check for valid string literal
    return true if str.match?(/\A"(?:[^"\\]|\\.)*"\z/)

    false
  end
end
