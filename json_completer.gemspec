# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "json_completer"
  spec.version       = '1.0.0'
  spec.authors       = ["Aha! (www.aha.io)"]
  spec.email         = ["support@aha.io"]

  spec.summary       = %q{Converts partial JSON strings into valid JSON with incremental parsing support}
  spec.description   = %q{A Ruby library that completes incomplete JSON strings by handling truncated primitives, missing values, and unclosed structures. Supports incremental processing for streaming scenarios.}
  spec.homepage      = "https://github.com/aha-app/json_completer"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/aha-app/json_completer"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob("lib/**/*") + [
    "LICENSE",
    "README.md",
  ]

  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.4"
  spec.add_development_dependency "rubocop", "~> 1.80"
 end
