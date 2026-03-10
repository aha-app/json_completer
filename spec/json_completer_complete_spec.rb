# frozen_string_literal: true

require 'spec_helper'

RSpec.describe JsonCompleter do
  describe '.complete' do
    it 'parses a valid JSON', :aggregate_failures do
      expect(JsonCompleter.complete('{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}')).to \
        eq('{"a":2.3e100,"b":"str","c":null,"d":false,"e":[1,2,3]}')
    end

    it 'parses whitespace', :aggregate_failures do
      expect(JsonCompleter.complete("  { \n } \t ")).to eq("  { \n } \t ")
    end

    it 'parses object', :aggregate_failures do
      expect(JsonCompleter.complete('{}')).to eq('{}')
      expect(JsonCompleter.complete('{  }')).to eq('{  }')
      expect(JsonCompleter.complete('{"a": {}}')).to eq('{"a": {}}')
      expect(JsonCompleter.complete('{"a": "b"}')).to eq('{"a": "b"}')
      expect(JsonCompleter.complete('{"a": 2}')).to eq('{"a": 2}')
    end

    it 'parses array', :aggregate_failures do
      expect(JsonCompleter.complete('[]')).to eq('[]')
      expect(JsonCompleter.complete('[  ]')).to eq('[  ]')
      expect(JsonCompleter.complete('[1,2,3]')).to eq('[1,2,3]')
      expect(JsonCompleter.complete('[ 1 , 2 , 3 ]')).to eq('[ 1 , 2 , 3 ]')
      expect(JsonCompleter.complete('[1,2,[3,4,5]]')).to eq('[1,2,[3,4,5]]')
      expect(JsonCompleter.complete('[{}]')).to eq('[{}]')
      expect(JsonCompleter.complete('{"a":[]}')).to eq('{"a":[]}')
      expect(JsonCompleter.complete('[1, "hi", true, false, null, {}, []]')).to eq('[1, "hi", true, false, null, {}, []]')
    end

    it 'parses number', :aggregate_failures do
      expect(JsonCompleter.complete('23')).to eq('23')
      expect(JsonCompleter.complete('0')).to eq('0')
      expect(JsonCompleter.complete('0e+2')).to eq('0e+2')
      expect(JsonCompleter.complete('0.0')).to eq('0.0')
      expect(JsonCompleter.complete('-0')).to eq('-0')
      expect(JsonCompleter.complete('2.3')).to eq('2.3')
      expect(JsonCompleter.complete('2300e3')).to eq('2300e3')
      expect(JsonCompleter.complete('2300e+3')).to eq('2300e+3')
      expect(JsonCompleter.complete('2300e-3')).to eq('2300e-3')
      expect(JsonCompleter.complete('-2')).to eq('-2')
      expect(JsonCompleter.complete('2e-3')).to eq('2e-3')
      expect(JsonCompleter.complete('2.3e-3')).to eq('2.3e-3')
    end

    it 'parses string', :aggregate_failures do
      expect(JsonCompleter.complete('"str"')).to eq('"str"')
      expect(JsonCompleter.complete('"\\"\\\\\\/\\b\\f\\n\\r\\t"')).to eq('"\\"\\\\\\/\\b\\f\\n\\r\\t"')
      expect(JsonCompleter.complete('"\\u260E"')).to eq('"\\u260E"')
    end

    it 'parses keywords', :aggregate_failures do
      expect(JsonCompleter.complete('true')).to eq('true')
      expect(JsonCompleter.complete('false')).to eq('false')
      expect(JsonCompleter.complete('null')).to eq('null')
    end

    it 'correctly handles strings equaling a JSON delimiter', :aggregate_failures do
      expect(JsonCompleter.complete('""')).to eq('""')
      expect(JsonCompleter.complete('"["')).to eq('"["')
      expect(JsonCompleter.complete('"]"')).to eq('"]"')
      expect(JsonCompleter.complete('"{"')).to eq('"{"')
      expect(JsonCompleter.complete('"}"')).to eq('"}"')
      expect(JsonCompleter.complete('":"')).to eq('":"')
      expect(JsonCompleter.complete('","')).to eq('","')
    end

    it 'supports unicode characters in a string', :aggregate_failures do
      expect(JsonCompleter.complete('"★"')).to eq('"★"')
      expect(JsonCompleter.complete('"\u2605"')).to eq('"\u2605"')
      expect(JsonCompleter.complete('"😀"')).to eq('"😀"')
      expect(JsonCompleter.complete('"\ud83d\ude00"')).to eq('"\ud83d\ude00"')
      expect(JsonCompleter.complete('"йнформация"')).to eq('"йнформация"')
    end

    it 'supports escaped unicode characters in a string', :aggregate_failures do
      expect(JsonCompleter.complete('"\u2605"')).to eq('"\u2605"')
      expect(JsonCompleter.complete('"\u2605A"')).to eq('"\u2605A"')
      expect(JsonCompleter.complete('"\ud83d\ude00"')).to eq('"\ud83d\ude00"')
      expect(JsonCompleter.complete('"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"')).to \
        eq('"\u0439\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f"')
    end

    it 'supports unicode characters in a key', :aggregate_failures do
      expect(JsonCompleter.complete('{"★":true}')).to eq('{"★":true}')
      expect(JsonCompleter.complete('{"\u2605":true}')).to eq('{"\u2605":true}')
      expect(JsonCompleter.complete('{"😀":true}')).to eq('{"😀":true}')
      expect(JsonCompleter.complete('{"\ud83d\ude00":true}')).to eq('{"\ud83d\ude00":true}')
    end

    it 'leaves string content untouched', :aggregate_failures do
      expect(JsonCompleter.complete('"[1,2,3,]"')).to eq('"[1,2,3,]"')
      expect(JsonCompleter.complete('"{a:2,}"')).to eq('"{a:2,}"')
      expect(JsonCompleter.complete('"{a:b}"')).to eq('"{a:b}"')
      expect(JsonCompleter.complete('"/* comment */"')).to eq('"/* comment */"')
    end

    it 'does not add extra items to an array' do
      expect(JsonCompleter.complete("[\n{},\n{}\n]")).to eq("[\n{},\n{}\n]")
    end

    context 'when repairing invalid JSON' do
      it 'repairs truncated JSON', :aggregate_failures do
        expect(JsonCompleter.complete('"foo')).to eq('"foo"')
        expect(JsonCompleter.complete('[')).to eq('[]')
        expect(JsonCompleter.complete('["foo')).to eq('["foo"]')
        expect(JsonCompleter.complete('["foo"')).to eq('["foo"]')
        expect(JsonCompleter.complete('["foo",')).to eq('["foo",null]')
        expect(JsonCompleter.complete('{"foo":"bar')).to eq('{"foo":"bar"}')
        expect(JsonCompleter.complete('{"foo":"bar')).to eq('{"foo":"bar"}')
        expect(JsonCompleter.complete('{"foo":')).to eq('{"foo":null}')
        expect(JsonCompleter.complete('{"foo"')).to eq('{"foo":null}')
        expect(JsonCompleter.complete('{"foo')).to eq('{"foo":null}')
        expect(JsonCompleter.complete('{')).to eq('{}')
        expect(JsonCompleter.complete('2.')).to eq('2.0')
        expect(JsonCompleter.complete('2e')).to eq('2e0')
        expect(JsonCompleter.complete('2e+')).to eq('2e+0')
        expect(JsonCompleter.complete('2e-')).to eq('2e-0')
        expect(JsonCompleter.complete('{"foo":"bar\u20')).to eq('{"foo":"bar"}')
        expect(JsonCompleter.complete('"\\u')).to eq('""')
        expect(JsonCompleter.complete('"\\u2')).to eq('""')
        expect(JsonCompleter.complete('"\\u260')).to eq('""')
        expect(JsonCompleter.complete('"\\u2605')).to eq('"\\u2605"')
        expect(JsonCompleter.complete('{"s \\ud')).to eq('{"s ":null}')
        expect(JsonCompleter.complete('{"message": "it\'s working')).to eq('{"message": "it\'s working"}')
        expect(JsonCompleter.complete('{"text":"Hello Sergey,I hop')).to eq('{"text":"Hello Sergey,I hop"}')
        expect(JsonCompleter.complete('{"message": "with, multiple, commma\'s, you see?')).to \
          eq('{"message": "with, multiple, commma\'s, you see?"}')
      end

      it 'does not repair a missing object value', :aggregate_failures do
        expect(JsonCompleter.complete('{"a":}')).to eq('{"a":}')
        expect(JsonCompleter.complete('{"a":,"b":2}')).to eq('{"a":,"b":2}')
      end

      it 'does not repair trailing commas in an array', :aggregate_failures do
        expect(JsonCompleter.complete('[1,2,3,]')).to eq('[1,2,3,]')
        expect(JsonCompleter.complete("[1,2,3,\n]")).to eq("[1,2,3,\n]")
        expect(JsonCompleter.complete("[1,2,3,  \n  ]")).to eq("[1,2,3,  \n  ]")
        expect(JsonCompleter.complete('{"array":[1,2,3,]}')).to eq('{"array":[1,2,3,]}')
      end

      it 'adds a missing closing brace for an object', :aggregate_failures do
        expect(JsonCompleter.complete('{')).to eq('{}')
        expect(JsonCompleter.complete('{"a":2')).to eq('{"a":2}')
        expect(JsonCompleter.complete('{"a":2,')).to eq('{"a":2}')
        expect(JsonCompleter.complete('{"a":{"b":2}')).to eq('{"a":{"b":2}}')
        expect(JsonCompleter.complete("{\n  \"a\":{\"b\":2\n}")).to eq("{\n  \"a\":{\"b\":2\n}}")
        expect(JsonCompleter.complete('[{"b":2')).to eq('[{"b":2}]')
        expect(JsonCompleter.complete("[{\"b\":2\n")).to eq("[{\"b\":2\n}]")
      end

      it 'adds a missing closing bracket for an array', :aggregate_failures do
        expect(JsonCompleter.complete('[')).to eq('[]')
        expect(JsonCompleter.complete('[1,2,3')).to eq('[1,2,3]')
        expect(JsonCompleter.complete('[1,2,3,')).to eq('[1,2,3,null]')
        expect(JsonCompleter.complete('[[1,2,3,')).to eq('[[1,2,3,null]]')
        expect(JsonCompleter.complete("{\n\"values\":[1,2,3\n")).to eq("{\n\"values\":[1,2,3\n]}")
      end

      it 'repairs numbers at the end', :aggregate_failures do
        expect(JsonCompleter.complete('{"a":2.')).to eq('{"a":2.0}')
        expect(JsonCompleter.complete('{"a":2e')).to eq('{"a":2e0}')
        expect(JsonCompleter.complete('{"a":2e-')).to eq('{"a":2e-0}')
        expect(JsonCompleter.complete('{"a":-')).to eq('{"a":0}')
        expect(JsonCompleter.complete('[2e,')).to eq('[2e0,null]')
        expect(JsonCompleter.complete('[2e ')).to eq('[2e0 ]')
        expect(JsonCompleter.complete('[-,')).to eq('[0,null]')
      end
    end
  end

  describe '#complete' do
    it 'completes JSON incrementally with state tracking' do
      completer = JsonCompleter.new

      expect(completer.complete('{"name":')).to eq('{"name":null}')
      expect(completer.complete('{"name":"John"')).to eq('{"name":"John"}')
      expect(completer.complete('{"name":"John","age":30}')).to eq('{"name":"John","age":30}')
    end

    it 'handles incremental array completion' do
      completer = JsonCompleter.new

      expect(completer.complete('[1,')).to eq('[1,null]')
      expect(completer.complete('[1,2,')).to eq('[1,2,null]')
      expect(completer.complete('[1,2,3]')).to eq('[1,2,3]')
    end

    it 'returns same result when input length unchanged' do
      completer = JsonCompleter.new

      expect(completer.complete('{"foo":')).to eq('{"foo":null}')
      expect(completer.complete('{"foo":')).to eq('{"foo":null}')
    end

    it 'handles state reset when input is truncated' do
      completer = JsonCompleter.new

      expect(completer.complete('{"name":"John","age":30}')).to eq('{"name":"John","age":30}')
      expect(completer.complete('{"name":')).to eq('{"name":null}')
    end

    it 'handles empty input' do
      completer = JsonCompleter.new

      expect(completer.complete('')).to eq('')
    end

    it 'handles valid primitives without processing' do
      completer = JsonCompleter.new

      expect(completer.complete('true')).to eq('true')
      expect(completer.complete('42')).to eq('42')
      expect(completer.complete('"hello"')).to eq('"hello"')
    end

    it 'processes complex nested structures incrementally' do
      completer = JsonCompleter.new

      expect(completer.complete('{"user":{"name":"John"')).to eq('{"user":{"name":"John"}}')
      expect(completer.complete('{"user":{"name":"John","details":{"age":')).to eq('{"user":{"name":"John","details":{"age":null}}}')
      expect(completer.complete('{"user":{"name":"John","details":{"age":30}}}')).to eq('{"user":{"name":"John","details":{"age":30}}}')
    end

    it 'maintains parsing state correctly across increments' do
      completer = JsonCompleter.new

      expect(completer.complete('[{"id":')).to eq('[{"id":null}]')
      expect(completer.complete('[{"id":1,"name":')).to eq('[{"id":1,"name":null}]')
    end

    it 'handles nil completer parameter' do
      completer = JsonCompleter.new

      expect(completer.complete('{"test":')).to eq('{"test":null}')
    end

    context 'with streaming JSON completion' do
      it 'simulates real streaming scenario' do
        completer = JsonCompleter.new
        streaming_chunks = [
          '{"response":',
          '{"response":"Hello',
          '{"response":"Hello world',
          '{"response":"Hello world","status":',
          '{"response":"Hello world","status":"success"}'
        ]

        results = streaming_chunks.map { |chunk| completer.complete(chunk) }

        expect(results).to eq(
          [
            '{"response":null}',
            '{"response":"Hello"}',
            '{"response":"Hello world"}',
            '{"response":"Hello world","status":null}',
            '{"response":"Hello world","status":"success"}'
          ]
        )
      end
    end

    context 'with HTML content in JSON strings' do
      it 'maintains valid JSON when streaming HTML in random chunks' do
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
        full_json = JSON.generate(html: html_content)
        accumulated_html = ''
        intermediate_results = []

        result = completer.complete('{"html":"')
        expect(result).to eq('{"html":""}')
        intermediate_results << result

        srand(12345)

        while current_position < html_content.length
          chunk_size = rand(3..7)
          end_position = [current_position + chunk_size, html_content.length].min
          accumulated_html += html_content[current_position...end_position]

          current_json = JSON.generate(html: accumulated_html)[0...-2]
          result = completer.complete(current_json)
          intermediate_results << result

          expect { JSON.parse(result) }.not_to raise_error
          current_position = end_position
        end

        result = completer.complete(JSON.generate(html: html_content))

        expect(result).to eq(full_json)
        expect(JSON.parse(result)['html']).to eq(html_content)
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

        completer.complete('{"html":"')

        while current_position < html_content.length
          chunk_size = chunk_sizes[chunk_index % chunk_sizes.length]
          chunk_index += 1

          end_position = [current_position + chunk_size, html_content.length].min
          accumulated_html += html_content[current_position...end_position]

          result = completer.complete(JSON.generate(html: accumulated_html)[0...-2])
          expect { JSON.parse(result) }.not_to raise_error

          current_position = end_position
        end

        result = completer.complete(JSON.generate(html: html_content))
        expect(JSON.parse(result)['html']).to eq(html_content)
      end
    end
  end
end
