# frozen_string_literal: true

require 'spec_helper'

RSpec.describe JsonCompleter do
  describe '.parse' do
    it 'parses valid JSON documents', :aggregate_failures do
      [
        '{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}',
        "  { \n } \t ",
        '{}',
        '{  }',
        '{"a": {}}',
        '{"a": "b"}',
        '{"a": 2}',
        '[]',
        '[  ]',
        '[1,2,3]',
        '[ 1 , 2 , 3 ]',
        '[1,2,[3,4,5]]',
        '[{}]',
        '{"a":[]}',
        '[1, "hi", true, false, null, {}, []]',
        '23',
        '0',
        '0e+2',
        '0.0',
        '-0',
        '2.3',
        '2300e3',
        '2300e+3',
        '2300e-3',
        '-2',
        '2e-3',
        '2.3e-3',
        '"str"',
        '"\\"\\\\\\/\\b\\f\\n\\r\\t"',
        '"\\u260E"',
        'true',
        'false',
        'null',
        '""',
        '"["',
        '"]"',
        '"{"',
        '"}"',
        '":"',
        '","',
        '"★"',
        '"\u2605"',
        '"😀"',
        '"\ud83d\ude00"',
        '"йнформация"',
        '"\u2605A"',
        '"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"',
        '{"★":true}',
        '{"\u2605":true}',
        '{"😀":true}',
        '{"\ud83d\ude00":true}',
        '"[1,2,3,]"',
        '"{a:2,}"',
        '"{a:b}"',
        '"/* comment */"',
        "[\n{},\n{}\n]"
      ].each do |input|
        expect_parse_to_match_json(input)
      end
    end

    context 'when repairing invalid JSON' do
      it 'repairs truncated JSON', :aggregate_failures do
        {
          '"foo' => 'foo',
          '[' => [],
          '["foo' => ['foo'],
          '["foo"' => ['foo'],
          '["foo",' => ['foo', nil],
          '{"foo":"bar' => { 'foo' => 'bar' },
          '{"foo":' => { 'foo' => nil },
          '{"foo"' => { 'foo' => nil },
          '{"foo' => { 'foo' => nil },
          '{' => {},
          '2.' => 2.0,
          '2e' => 2.0,
          '2e+' => 2.0,
          '2e-' => 2.0,
          '{"foo":"bar\u20' => { 'foo' => 'bar' },
          '"\\u' => '',
          '"\\u2' => '',
          '"\\u260' => '',
          '"\\u2605' => '★',
          '{"s \\ud' => { 's ' => nil },
          '{"message": "it\'s working' => { 'message' => "it's working" },
          '{"text":"Hello Sergey,I hop' => { 'text' => 'Hello Sergey,I hop' },
          '{"message": "with, multiple, commma\'s, you see?' => { 'message' => "with, multiple, commma's, you see?" }
        }.each do |input, expected|
          expect(JsonCompleter.parse(input)).to eq(expected)
        end
      end

      it 'raises on a missing object value', :aggregate_failures do
        ['{"a":}', '{"a":,"b":2}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises when an object value starts before a colon', :aggregate_failures do
        ['{"a" 1}', '{"a" "b"}', '{"a" {"b":2}}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on trailing commas in a closed array', :aggregate_failures do
        ['[1,2,3,]', "[1,2,3,\n]", "[1,2,3,  \n  ]", '{"array":[1,2,3,]}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on extra tokens after the top-level value', :aggregate_failures do
        ['1 2', 'true false', '[1]2', '{"a":1}x'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on unexpected tokens instead of skipping them', :aggregate_failures do
        ['x', '[x]', '{"a":[x]}', '{"a":1x}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on missing commas and misplaced separators', :aggregate_failures do
        ['[1 2]', '{"a":1 "b":2}', '[1:2]', '{"a"::1}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on invalid keyword literals before delimiters', :aggregate_failures do
        ['[tru]', '{"a":tru}', '[falx]', '{"a":nullx}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on invalid numbers with leading zeroes', :aggregate_failures do
        ['{"a":01}', '{"a":-01}', '[00.1]'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on invalid string escape sequences', :aggregate_failures do
        ['"\\q"', '{"a":"\\q"}', '"\\u12x4"', '{"a":"\\u12x4"}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on invalid unicode surrogate pairs', :aggregate_failures do
        ['{"a":"\uD83D"}', '{"a":"\uDC00"}', '{"a":"\uD83D\u2605"}'].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'raises on raw control characters inside strings', :aggregate_failures do
        [
          "{\"a\":\"hello\nworld\"}",
          "{\"a\":\"tab\tchar\"}",
          "{\"a\":\"carriage\rreturn\"}",
          "{\"a\":\"\u0001\"}"
        ].each do |input|
          expect { JsonCompleter.parse(input) }.to raise_error(JsonCompleter::ParseError)
        end
      end

      it 'adds a missing closing brace for an object', :aggregate_failures do
        {
          '{' => {},
          '{"a":2' => { 'a' => 2 },
          '{"a":2,' => { 'a' => 2 },
          '{"a":{"b":2}' => { 'a' => { 'b' => 2 } },
          "{\n  \"a\":{\"b\":2\n}" => { 'a' => { 'b' => 2 } },
          '[{"b":2' => [{ 'b' => 2 }],
          "[{\"b\":2\n" => [{ 'b' => 2 }]
        }.each do |input, expected|
          expect(JsonCompleter.parse(input)).to eq(expected)
        end
      end

      it 'adds a missing closing bracket for an array', :aggregate_failures do
        {
          '[' => [],
          '[1,2,3' => [1, 2, 3],
          '[1,2,3,' => [1, 2, 3, nil],
          '[[1,2,3,' => [[1, 2, 3, nil]],
          "{\n\"values\":[1,2,3\n" => { 'values' => [1, 2, 3] }
        }.each do |input, expected|
          expect(JsonCompleter.parse(input)).to eq(expected)
        end
      end

      it 'repairs numbers at the end', :aggregate_failures do
        {
          '{"a":2.}' => { 'a' => 2.0 },
          '{"a":2e}' => { 'a' => 2.0 },
          '{"a":2e-}' => { 'a' => 2.0 },
          '{"a":-}' => { 'a' => 0 },
          '[2e,' => [2.0, nil],
          '[2e ' => [2.0],
          '[-,' => [0, nil]
        }.each do |input, expected|
          expect(JsonCompleter.parse(input)).to eq(expected)
        end
      end
    end
  end

  describe '#parse' do
    it 'parses JSON incrementally with state tracking' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"name":', { 'name' => nil })
      expect_incremental_parse_result(completer, '{"name":"John"', { 'name' => 'John' })
      expect_incremental_parse_result(completer, '{"name":"John","age":30}', { 'name' => 'John', 'age' => 30 })
    end

    it 'handles incremental array completion' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '[1,', [1, nil])
      expect_incremental_parse_result(completer, '[1,2,', [1, 2, nil])
      expect_incremental_parse_result(completer, '[1,2,3]', [1, 2, 3])
    end

    it 'returns the same object when input length is unchanged' do
      completer = JsonCompleter.new

      result1 = completer.parse('{"foo":')
      result2 = completer.parse('{"foo":')

      expect(result2).to equal(result1)
      expect(result2).to eq({ 'foo' => nil })
    end

    it 'reuses the same root object across increments' do
      completer = JsonCompleter.new

      result1 = completer.parse('{"users":[{"name":"')
      result2 = completer.parse('{"users":[{"name":"Alice"}')

      expect(result2).to equal(result1)
      expect(result2['users']).to equal(result1['users'])
      expect(result2['users'].first).to equal(result1['users'].first)
      expect(result2).to eq({ 'users' => [{ 'name' => 'Alice' }] })
    end

    it 'handles state reset when input is truncated' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"name":"John","age":30}', { 'name' => 'John', 'age' => 30 })
      expect_incremental_parse_result(completer, '{"name":', { 'name' => nil })
    end

    it 'reuses the same root object when growth only adds trailing whitespace' do
      completer = JsonCompleter.new

      result1 = completer.parse('{"a":1}')
      result2 = completer.parse('{"a":1} ')

      expect(result2).to equal(result1)
      expect(result2).to eq({ 'a' => 1 })
    end

    it 'handles empty input' do
      completer = JsonCompleter.new

      expect(completer.parse('')).to be_nil
    end

    it 'handles valid primitives without reparsing the full document' do
      completer = JsonCompleter.new

      expect(completer.parse('true')).to eq(true)
      expect(completer.parse('42')).to eq(42)
      expect(completer.parse('"hello"')).to eq('hello')
    end

    it 'processes complex nested structures incrementally' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"user":{"name":"John"', { 'user' => { 'name' => 'John' } })
      expect_incremental_parse_result(
        completer,
        '{"user":{"name":"John","details":{"age":',
        { 'user' => { 'name' => 'John', 'details' => { 'age' => nil } } }
      )
      expect_incremental_parse_result(
        completer,
        '{"user":{"name":"John","details":{"age":30}}}',
        { 'user' => { 'name' => 'John', 'details' => { 'age' => 30 } } }
      )
    end

    it 'maintains parsing state correctly across increments' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '[{"id":', [{ 'id' => nil }])
      expect_incremental_parse_result(completer, '[{"id":1,"name":', [{ 'id' => 1, 'name' => nil }])
    end

    it 'handles incremental multibyte strings' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"emoji":"😀', { 'emoji' => '😀' })
      expect_incremental_parse_result(completer, '{"emoji":"😀 привет', { 'emoji' => '😀 привет' })
      expect_incremental_parse_result(completer, '{"emoji":"😀 привет"}', { 'emoji' => '😀 привет' })
    end

    it 'handles nil completer parameter' do
      completer = JsonCompleter.new

      expect(completer.parse('{"test":')).to eq({ 'test' => nil })
    end

    it 'raises when a later chunk adds another top-level value' do
      completer = JsonCompleter.new

      expect(completer.parse('1')).to eq(1)
      expect { completer.parse('1 2') }.to raise_error(JsonCompleter::ParseError)
    end

    it 'restores overwritten keys when an incomplete key grows' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"a":1,"a', { 'a' => nil })
      expect_incremental_parse_result(completer, '{"a":1,"ab', { 'a' => 1, 'ab' => nil })
      expect_incremental_parse_result(completer, '{"a":1,"ab":2}', { 'a' => 1, 'ab' => 2 })
    end

    it 'recovers after an invalid number' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"a":0}', { 'a' => 0 })
      expect { completer.parse('{"a":01}') }.to raise_error(JsonCompleter::ParseError, 'invalid number literal')
      expect_incremental_parse_result(completer, '{"a":0,"b":1}', { 'a' => 0, 'b' => 1 })
    end

    it 'recovers after an invalid string escape' do
      completer = JsonCompleter.new

      expect_incremental_parse_result(completer, '{"a":"ok"}', { 'a' => 'ok' })
      expect { completer.parse('{"a":"\\q"}') }.to raise_error(JsonCompleter::ParseError, 'invalid string escape sequence')
      expect_incremental_parse_result(completer, '{"a":"fixed"}', { 'a' => 'fixed' })
    end

    context 'with streaming JSON parsing' do
      it 'simulates a real streaming scenario' do
        completer = JsonCompleter.new
        streaming_chunks = [
          '{"response":',
          '{"response":"Hello',
          '{"response":"Hello world',
          '{"response":"Hello world","status":',
          '{"response":"Hello world","status":"success"}'
        ]

        results = streaming_chunks.map { |chunk| snapshot(completer.parse(chunk)) }

        expect(results).to eq(
          [
            { 'response' => nil },
            { 'response' => 'Hello' },
            { 'response' => 'Hello world' },
            { 'response' => 'Hello world', 'status' => nil },
            { 'response' => 'Hello world', 'status' => 'success' }
          ]
        )
      end
    end

    context 'with HTML content in JSON strings' do
      it 'maintains parsed JSON when streaming HTML in random chunks' do
        html_content = <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>HTML Test with "quotes" & special chars</title>
            </head>
            <body>
              <h1>Test Document</h1>
              <div id="container" class="main-content" data-value='{"key":"value"}'>
                <p>This is a paragraph with <strong>bold text</strong> and <em>emphasis</em>.</p>
                <ul>
                  <li>Item 1</li>
                  <li>Item 2</li>
                  <li>Item with nested <a href="https://example.com">link</a></li>
                </ul>
                <!-- Comments should be preserved -->
                <img src="image.jpg" alt="Self-closing tag" />
              </div>
              <script>
                // JavaScript with JSON-like content
                const data = {
                  "name": "Test",
                  "values": [1, 2, 3],
                  "nested": { "key": "value" }
                };
                function escapeTest() {
                  return "This string has \\"quotes\\" and backslashes \\\\ inside";
                }
              </script>
            </body>
          </html>
        HTML

        completer = JsonCompleter.new
        current_position = 0
        accumulated_html = ''
        intermediate_results = []

        result = completer.parse('{"html":"')
        expect(result).to eq({ 'html' => '' })
        intermediate_results << result['html'].dup

        srand(12345)

        while current_position < html_content.length
          chunk_size = rand(3..7)
          end_position = [current_position + chunk_size, html_content.length].min
          accumulated_html += html_content[current_position...end_position]

          result = completer.parse(JSON.generate(html: accumulated_html)[0...-2])

          expect(result).to eq({ 'html' => accumulated_html })
          intermediate_results << result['html'].dup
          current_position = end_position
        end

        result = completer.parse(JSON.generate(html: html_content))

        expect(result).to eq({ 'html' => html_content })
        expect(intermediate_results.size).to be > 10
      end

      it 'handles HTML with complex nested structures and edge cases' do
        html_content = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Edge Cases & Special Characters Test</title>
              <meta name="description" content="Testing &quot;special&quot; characters & entities" />
            </head>
            <body>
              <div id="test" class="level-1">
                <div class="level-2">
                  <div class="level-3">
                    <div class="level-4">
                      <p>Deeply nested content</p>
                    </div>
                  </div>
                </div>
              </div>
              <input type="text" value="Text with \\"escaped quotes\\"" data-json='{"key":"value"}' />
              <br /><hr />
              <p>HTML entities: &lt; &gt; &amp; &quot; &apos; &copy;</p>
              <script type="application/json">
              {
                "array": [1, 2, 3],
                "object": {
                  "nested": {
                    "key": "value with \\"quotes\\""
                  }
                },
                "string": "This is a test"
              }
              </script>
            </body>
          </html>
        HTML
        html_content += html_content

        completer = JsonCompleter.new
        current_position = 0
        accumulated_html = ''
        chunk_sizes = [3, 5, 4, 7, 6, 3, 5, 4, 6, 7, 5, 3, 4, 6, 5, 7, 4, 3, 5, 6]
        chunk_index = 0

        expect(completer.parse('{"html":"')).to eq({ 'html' => '' })

        while current_position < html_content.length
          chunk_size = chunk_sizes[chunk_index % chunk_sizes.length]
          chunk_index += 1

          end_position = [current_position + chunk_size, html_content.length].min
          accumulated_html += html_content[current_position...end_position]

          result = completer.parse(JSON.generate(html: accumulated_html)[0...-2])
          expect(result['html']).to eq(accumulated_html)

          current_position = end_position
        end

        result = completer.parse(JSON.generate(html: html_content))
        expect(result).to eq({ 'html' => html_content })
      end
    end
  end
end
