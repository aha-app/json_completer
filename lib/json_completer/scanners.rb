# frozen_string_literal: true

class JsonCompleter
  module Scanners
    class CompletionStringToken < Struct.new(:buffer, :escape_state, :unicode_digits, keyword_init: true)
      def initialize(buffer: nil, escape_state: nil, unicode_digits: nil)
        buffer ||= StringIO.new
        buffer << '"' if buffer.string.empty?
        super
      end

      def start_escape!
        buffer << '\\'
        self.escape_state = :backslash
      end

      def append_char(char)
        buffer << char
      end

      def append_simple_escape(char)
        buffer << char
      end

      def valid_simple_escape?(_char)
        true
      end

      def start_unicode_escape!
        self.unicode_digits = String.new
        buffer << 'u'
      end

      def append_unicode_digit(char)
        unicode_digits << char
        buffer << char
      end

      def finish_unicode_escape!; end

      def invalid_unicode!
        current = buffer.string
        current = current.sub(/\\u[0-9a-fA-F]*\z/, '')
        self.buffer = StringIO.new
        buffer << current
        self.unicode_digits = nil
        self.escape_state = nil
      end

      def terminate!
        buffer << '"'
      end

      def finalized_incomplete_value
        value = buffer.string.dup
        trailing_backslashes = 0
        index = value.length - 1

        while index >= 0 && value[index] == '\\'
          trailing_backslashes += 1
          index -= 1
        end

        value = value[0...-1] if trailing_backslashes.odd?
        value = value.sub(/\\u[0-9a-fA-F]{0,3}\z/, '')
        "#{value}\""
      end
    end

    class ParsedStringToken < Struct.new(
      :role, :slot, :context, :buffer, :escape_state, :unicode_digits, :pending_high_surrogate, :visible_key,
      :visible_key_replaced_value, :visible_key_replaced_present,
      keyword_init: true
    )
      def initialize(
        role:, slot: nil, context: nil, buffer: nil, escape_state: nil, unicode_digits: nil,
        pending_high_surrogate: nil, visible_key: nil, visible_key_replaced_value: nil, visible_key_replaced_present: false
      )
        super
        self.buffer ||= String.new
      end

      def start_escape!
        self.escape_state = :backslash
      end

      def append_char(char)
        buffer << char
      end

      def append_simple_escape(char)
        buffer << case char
                  when 'b'
                    "\b"
                  when 'f'
                    "\f"
                  when 'n'
                    "\n"
                  when 'r'
                    "\r"
                  when 't'
                    "\t"
                  else
                    char
                  end
      end

      def valid_simple_escape?(char)
        ['"', '\\', '/', 'b', 'f', 'n', 'r', 't'].include?(char)
      end

      def start_unicode_escape!
        self.unicode_digits = String.new
      end

      def append_unicode_digit(char)
        unicode_digits << char
      end

      def finish_unicode_escape!
        codepoint = unicode_digits.to_i(16)

        if pending_high_surrogate
          unless codepoint.between?(0xDC00, 0xDFFF)
            self.pending_high_surrogate = nil
            return :invalid_unicode
          end

          combined = 0x10000 + ((pending_high_surrogate - 0xD800) << 10) + (codepoint - 0xDC00)
          buffer << combined.chr(Encoding::UTF_8)
          self.pending_high_surrogate = nil
          return :ok
        end

        if codepoint.between?(0xD800, 0xDBFF)
          self.pending_high_surrogate = codepoint
        elsif codepoint.between?(0xDC00, 0xDFFF)
          return :invalid_unicode
        else
          buffer << codepoint.chr(Encoding::UTF_8)
        end
        :ok
      rescue RangeError
        self.pending_high_surrogate = nil
        :invalid_unicode
      end

      def invalid_unicode!
        self.escape_state = nil
        self.unicode_digits = nil
        self.pending_high_surrogate = nil
      end

      def terminate!; end
    end

    class NumberToken < Struct.new(:slot, :raw, :phase, :invalid, keyword_init: true)
      def initialize(slot: nil, raw: nil, phase: nil, invalid: false)
        super
        self.raw ||= String.new
      end

      def append(char)
        case phase
        when nil
          case char
          when '-'
            raw << char
            self.phase = :sign
          when '0'
            raw << char
            self.phase = :zero
          when /[0-9]/
            raw << char
            self.phase = :int
          else
            return false
          end
        when :sign
          case char
          when '0'
            raw << char
            self.phase = :zero
          when /[0-9]/
            raw << char
            self.phase = :int
          when '.'
            raw << char
            self.phase = :frac_start
          else
            return false
          end
        when :zero
          if char.match?(/[0-9]/)
            self.invalid = true
            return false
          elsif char == '.'
            raw << char
            self.phase = :frac_start
          elsif %w[e E].include?(char)
            raw << char
            self.phase = :exp_start
          else
            return false
          end
        when :int
          if char.match?(/[0-9]/)
            raw << char
          elsif char == '.'
            raw << char
            self.phase = :frac_start
          elsif %w[e E].include?(char)
            raw << char
            self.phase = :exp_start
          else
            return false
          end
        when :frac_start
          return false unless char.match?(/[0-9]/)

          raw << char
          self.phase = :frac
        when :frac
          if char.match?(/[0-9]/)
            raw << char
          elsif %w[e E].include?(char)
            raw << char
            self.phase = :exp_start
          else
            return false
          end
        when :exp_start
          if ['+', '-'].include?(char)
            raw << char
            self.phase = :exp_sign
          elsif char.match?(/[0-9]/)
            raw << char
            self.phase = :exp
          else
            return false
          end
        when :exp_sign
          return false unless char.match?(/[0-9]/)

          raw << char
          self.phase = :exp
        when :exp
          return false unless char.match?(/[0-9]/)

          raw << char
        end

        true
      end

      def completed_literal
        literal = raw.dup

        case phase
        when :sign
          literal = '0'
        when :frac_start
          literal = literal == '-.' ? '-0.0' : "#{literal}0"
        when :exp_start, :exp_sign
          literal = "#{literal}0"
        end

        literal = "0#{literal}" if literal.start_with?('.')
        literal = '0' if literal.empty? || literal == '-'
        literal
      end

      def parsed_value
        literal = completed_literal
        literal.match?(/[.eE]/) ? literal.to_f : literal.to_i
      end

      def invalid?
        invalid
      end
    end

    class KeywordToken < Struct.new(:slot, :target, :matched, keyword_init: true)
      def initialize(target:, slot: nil, matched: 0)
        super
      end

      def append(char)
        return false if matched >= target.length
        return false unless char.downcase == target[matched]

        self.matched += 1
        true
      end

      def parsed_value
        case target
        when 'true'
          true
        when 'false'
          false
        end
      end
    end

    module_function

    def scan_string(input, index, token)
      strict = token.is_a?(ParsedStringToken)

      while index < input.length
        char = input[index]

        if token.unicode_digits
          if char.match?(/[0-9a-fA-F]/)
            token.append_unicode_digit(char)
            index += 1

            if token.unicode_digits.length == 4
              status = token.finish_unicode_escape!
              token.escape_state = nil
              token.unicode_digits = nil
              return [index, :invalid_unicode] if status == :invalid_unicode
            end

            next
          end

          token.invalid_unicode!
          token.terminate!
          return [index, :invalid_unicode]
        end

        if token.escape_state == :backslash
          if strict && token.pending_high_surrogate && char != 'u'
            return [index, :invalid_unicode]
          end

          if char == 'u'
            token.start_unicode_escape!
            index += 1
            next
          end

          return [index, :invalid_escape] unless token.valid_simple_escape?(char)

          token.append_simple_escape(char)
          token.escape_state = nil
          index += 1
          next
        end

        case char
        when '\\'
          token.start_escape!
          index += 1
        when '"'
          if strict && token.pending_high_surrogate
            return [index, :invalid_unicode]
          end

          token.terminate!
          return [index + 1, :terminated]
        else
          if strict
            return [index, :invalid_control_character] if char.ord < 0x20
            return [index, :invalid_unicode] if token.pending_high_surrogate
          end

          token.append_char(char)
          index += 1
        end
      end

      [index, :incomplete]
    end

    def scan_number_literal(input, index)
      start_index = index
      token = NumberToken.new

      while index < input.length && token.append(input[index])
        index += 1
      end

      [token.completed_literal, index - start_index]
    end

    def scan_keyword_literal(input, index, target_keyword)
      start_index = index
      token = KeywordToken.new(target: target_keyword)

      while index < input.length && token.append(input[index])
        index += 1
      end

      return [input[start_index], 1] if token.matched.zero?

      [target_keyword, index - start_index]
    end
  end
end
