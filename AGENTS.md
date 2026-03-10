# Project

`json_completer` is a Ruby gem for turning partial or truncated JSON into valid JSON. It is built for streaming and incremental parsing, so changes should preserve correctness while keeping stateful completion fast and memory-efficient.

# Project Priorities

- Optimize for correctness first. Returning wrong JSON or corrupting incremental parser state is a regression, even if the code gets smaller or faster.
- Reliability is a core feature. Keep behavior deterministic, handle truncated and streaming input safely, and preserve clear invariants around parser state.
- Keep the memory footprint low. Prefer incremental state, bounded allocations, and avoid reparsing or copying the full input unless there is a strong reason.
- Keep execution fast. Protect the hot path, favor linear work on new input, and avoid abstractions that add noticeable overhead in tight loops.

## Required Validation

- For code changes, run `bundle exec rubocop` and `bundle exec rspec`.
- For any code change, run `JSON_COMPLETER_BENCHMARK=1 bundle exec rspec spec/parse_benchmark_spec.rb` before the change and after the change, then compare the results. Treat benchmark regressions in memory or throughput as blocking until explained or fixed.
- When behavior or performance claims change, update `README.md` in the same change.
