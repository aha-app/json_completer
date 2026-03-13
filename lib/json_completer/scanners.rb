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

      def append_slice(input, start_index, length)
        buffer << input.byteslice(start_index, length)
      end

      # completion keeps escape bytes verbatim, so convert the ASCII byte back into a 1-byte string.
      def append_simple_escape(byte)
        buffer << byte.chr(Encoding::UTF_8)
      end

      def valid_simple_escape?(_byte)
        true
      end

      def start_unicode_escape!
        self.unicode_digits = String.new
        buffer << 'u'
      end

      def append_unicode_digit(byte)
        unicode_digits << byte
        buffer << byte.chr(Encoding::UTF_8)
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

      def append_slice(input, start_index, length)
        buffer << input.byteslice(start_index, length)
      end

      # ASCII escape bytes: 98/102/110/114/116 = b/f/n/r/t.
      def append_simple_escape(byte)
        buffer << case byte
                  when 98
                    "\b"
                  when 102
                    "\f"
                  when 110
                    "\n"
                  when 114
                    "\r"
                  when 116
                    "\t"
                  else
                    byte
                  end
      end

      def valid_simple_escape?(byte)
        case byte
        when 34, 92, 47, 98, 102, 110, 114, 116
          true
        else
          false
        end
      end

      def start_unicode_escape!
        self.unicode_digits = String.new
      end

      def append_unicode_digit(byte)
        unicode_digits << byte
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

      # append_byte consumes ASCII bytes, not 1-character strings:
      # 45 = -, 46 = ., 48..57 = 0..9, 69/101 = E/e.
      def append_byte(byte)
        case phase
        when nil
          case byte
          when 45
            raw << byte
            self.phase = :sign
          when 48
            raw << byte
            self.phase = :zero
          when 49..57
            raw << byte
            self.phase = :int
          else
            return false
          end
        when :sign
          case byte
          when 48
            raw << byte
            self.phase = :zero
          when 49..57
            raw << byte
            self.phase = :int
          when 46
            raw << byte
            self.phase = :frac_start
          else
            return false
          end
        when :zero
          if Scanners.digit_byte?(byte)
            self.invalid = true
            return false
          elsif byte == 46
            raw << byte
            self.phase = :frac_start
          elsif Scanners.exponent_byte?(byte)
            raw << byte
            self.phase = :exp_start
          else
            return false
          end
        when :int
          if Scanners.digit_byte?(byte)
            raw << byte
          elsif byte == 46
            raw << byte
            self.phase = :frac_start
          elsif Scanners.exponent_byte?(byte)
            raw << byte
            self.phase = :exp_start
          else
            return false
          end
        when :frac_start
          return false unless Scanners.digit_byte?(byte)

          raw << byte
          self.phase = :frac
        when :frac
          if Scanners.digit_byte?(byte)
            raw << byte
          elsif Scanners.exponent_byte?(byte)
            raw << byte
            self.phase = :exp_start
          else
            return false
          end
        when :exp_start
          case byte
          when 43, 45
            raw << byte
            self.phase = :exp_sign
          when 48..57
            raw << byte
            self.phase = :exp
          else
            return false
          end
        when :exp_sign
          return false unless Scanners.digit_byte?(byte)

          raw << byte
          self.phase = :exp
        when :exp
          return false unless Scanners.digit_byte?(byte)

          raw << byte
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

      def append_byte(byte)
        return false if matched >= target.length
        return false unless (byte | 0x20) == target.getbyte(matched)

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
      # JSON string syntax is ASCII, so scanning bytes is safe here: multibyte UTF-8 content is
      # treated as opaque payload and copied via byteslice until we hit an ASCII delimiter/escape.
      length = input.bytesize
      segment_start = index

      while index < length
        byte = input.getbyte(index)

        if token.unicode_digits
          if hex_digit_byte?(byte)
            token.append_unicode_digit(byte)
            index += 1

            if token.unicode_digits.length == 4
              status = token.finish_unicode_escape!
              token.escape_state = nil
              token.unicode_digits = nil
              return [index, :invalid_unicode] if status == :invalid_unicode
            end

            segment_start = index
            next
          end

          token.invalid_unicode!
          token.terminate!
          return [index, :invalid_unicode]
        end

        if token.escape_state == :backslash
          if strict && token.pending_high_surrogate && byte != 117
            return [index, :invalid_unicode]
          end

          if byte == 117
            token.start_unicode_escape!
            index += 1
            segment_start = index
            next
          end

          return [index, :invalid_escape] unless token.valid_simple_escape?(byte)

          token.append_simple_escape(byte)
          token.escape_state = nil
          index += 1
          segment_start = index
          next
        end

        if strict && token.pending_high_surrogate && byte != 92
          return [index, :invalid_unicode]
        end

        if byte == 34
          token.append_slice(input, segment_start, index - segment_start) if index > segment_start

          if strict && token.pending_high_surrogate
            return [index, :invalid_unicode]
          end

          token.terminate!
          return [index + 1, :terminated]
        end

        if byte == 92
          token.append_slice(input, segment_start, index - segment_start) if index > segment_start
          token.start_escape!
          index += 1
          segment_start = index
          next
        end

        if strict && byte < 0x20
          token.append_slice(input, segment_start, index - segment_start) if index > segment_start
          return [index, :invalid_control_character]
        end

        index += 1
      end

      token.append_slice(input, segment_start, index - segment_start) if index > segment_start
      [index, :incomplete]
    end

    def scan_number_literal(input, index)
      start_index = index
      token = NumberToken.new
      length = input.bytesize

      while index < length && token.append_byte(input.getbyte(index))
        index += 1
      end

      [token.completed_literal, index - start_index]
    end

    def scan_keyword_literal(input, index, target_keyword)
      start_index = index
      token = KeywordToken.new(target: target_keyword)
      length = input.bytesize

      while index < length && token.append_byte(input.getbyte(index))
        index += 1
      end

      return [input.byteslice(start_index, 1), 1] if token.matched.zero?

      [target_keyword, index - start_index]
    end

    def digit_byte?(byte)
      byte.between?(48, 57)
    end

    def exponent_byte?(byte)
      case byte
      when 69, 101
        true
      else
        false
      end
    end

    def hex_digit_byte?(byte)
      digit_byte?(byte) || byte.between?(65, 70) || byte.between?(97, 102)
    end
  end
end
