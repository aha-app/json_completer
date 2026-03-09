# frozen_string_literal: true

require 'objspace'
require 'spec_helper'

RSpec.describe 'JsonCompleter.parse benchmark', :benchmark do
  def snapshot(value)
    Marshal.load(Marshal.dump(value))
  end

  def heap_page_bytes
    GC::INTERNAL_CONSTANTS.fetch(:HEAP_PAGE_SIZE)
  end

  def gc_snapshot
    GC.start(full_mark: true, immediate_sweep: true)

    {
      total_allocated_objects: GC.stat[:total_allocated_objects],
      total_allocated_pages: GC.stat[:total_allocated_pages],
      heap_live_slots: GC.stat[:heap_live_slots],
      memsize_of_all: ObjectSpace.memsize_of_all
    }
  end

  def build_payload
    sections = Array.new(400) do |index|
      "Section #{index}: #{('streaming json benchmark text ' * 6).strip}"
    end

    {
      'request' => {
        'id' => 'benchmark-request',
        'model' => 'gpt-test',
        'status' => 'streaming'
      },
      'content' => sections.join("\n"),
      'meta' => {
        'generated_at' => '2026-03-09T00:00:00Z',
        'source' => 'benchmark',
        'sections' => sections.length
      },
      'tokens' => [128, 256, 512, 1024]
    }
  end

  def build_prefixes(json, chunk_size)
    prefixes = []
    index = chunk_size

    while index < json.length
      prefixes << json[0...index]
      index += chunk_size
    end

    prefixes << json
    prefixes
  end

  def validate_completed_prefixes!(prefixes)
    completer = JsonCompleter.new

    prefixes.each_with_index do |prefix, index|
      JSON.parse(completer.complete(prefix))
    rescue JSON::ParserError => e
      raise <<~MSG
        complete produced invalid JSON for benchmark prefix #{index} (#{prefix.bytesize} bytes)
        error: #{e.message}
      MSG
    end

    prefixes
  end

  def measure_strategy(iterations, prefixes)
    yield(prefixes)

    before = gc_snapshot
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    final_result = nil

    iterations.times do
      final_result = yield(prefixes)
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    after = gc_snapshot

    {
      seconds: elapsed,
      allocated_objects: after[:total_allocated_objects] - before[:total_allocated_objects],
      heap_growth_pages: after[:total_allocated_pages] - before[:total_allocated_pages],
      heap_growth_bytes: (after[:total_allocated_pages] - before[:total_allocated_pages]) * heap_page_bytes,
      retained_objects: after[:heap_live_slots] - before[:heap_live_slots],
      retained_bytes: after[:memsize_of_all] - before[:memsize_of_all],
      final_result: snapshot(final_result)
    }
  end

  def format_ratio(numerator, denominator)
    return 'n/a' if denominator.zero?

    format('%.2fx', numerator.to_f / denominator)
  end

  def format_metrics(name, metrics, iterations)
    ms_per_iteration = (metrics[:seconds] * 1000.0) / iterations

    format(
      '%<name>s total=%<seconds>.4fs per_iter=%<ms>.3fms allocated_objects=%<objects>d heap_growth_bytes=%<heap_growth_bytes>d heap_growth_pages=%<pages>d retained_objects=%<retained_objects>d retained_bytes=%<retained_bytes>d',
      name: name.ljust(20),
      seconds: metrics[:seconds],
      ms: ms_per_iteration,
      objects: metrics[:allocated_objects],
      heap_growth_bytes: metrics[:heap_growth_bytes],
      pages: metrics[:heap_growth_pages],
      retained_objects: metrics[:retained_objects],
      retained_bytes: metrics[:retained_bytes]
    )
  end

  it 'reports runtime and memory signals against complete + JSON.parse' do
    skip 'Set JSON_COMPLETER_BENCHMARK=1 to run this benchmark spec' unless ENV['JSON_COMPLETER_BENCHMARK'] == '1'

    iterations = Integer(ENV.fetch('JSON_COMPLETER_BENCHMARK_ITERATIONS', '50'))
    chunk_size = Integer(ENV.fetch('JSON_COMPLETER_BENCHMARK_CHUNK_SIZE', '8'))
    json = JSON.generate(build_payload)
    prefixes = validate_completed_prefixes!(build_prefixes(json, chunk_size))

    parse_metrics = measure_strategy(iterations, prefixes) do |current_prefixes|
      completer = JsonCompleter.new
      current_prefixes.each { |prefix| completer.parse(prefix) }
    end

    baseline_metrics = measure_strategy(iterations, prefixes) do |current_prefixes|
      completer = JsonCompleter.new
      current_prefixes.each { |prefix| JSON.parse(completer.complete(prefix)) }
    end

    speedup = baseline_metrics[:seconds] / parse_metrics[:seconds]
    allocation_ratio = baseline_metrics[:allocated_objects].to_f / parse_metrics[:allocated_objects]
    heap_growth_ratio = format_ratio(baseline_metrics[:heap_growth_bytes], parse_metrics[:heap_growth_bytes])

    puts
    puts "payload_bytes=#{json.bytesize} prefixes=#{prefixes.length} iterations=#{iterations} chunk_size=#{chunk_size}"
    puts format_metrics('parse', parse_metrics, iterations)
    puts format_metrics('complete+JSON.parse', baseline_metrics, iterations)
    puts "speedup=#{format('%.2fx', speedup)} object_allocation_reduction=#{format('%.2fx', allocation_ratio)} heap_growth_reduction=#{heap_growth_ratio}"

    expect(parse_metrics[:final_result]).to eq(baseline_metrics[:final_result])
  end
end
