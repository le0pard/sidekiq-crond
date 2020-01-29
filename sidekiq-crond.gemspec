require_relative 'lib/sidekiq/crond/version'

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-crond"
  spec.version       = Sidekiq::Crond::VERSION
  spec.authors       = ["Alexey Vasiliev"]
  spec.email         = ["leopard.not.a@gmail.com"]

  spec.summary       = "Enables to set jobs to be run in specified time (using CRON notation)"
  spec.description   = "Enables to set jobs to be run in specified time (using CRON notation)"
  spec.homepage      = "https://github.com/le0pard/sidekiq-crond"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/le0pard/sidekiq-crond"
  spec.metadata["changelog_uri"] = "https://github.com/le0pard/sidekiq-crond"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "sidekiq", ">= 5"
  spec.add_runtime_dependency "fugit", ">= 1.1"

  spec.add_development_dependency "rubocop", ">= 0.57.2"
  spec.add_development_dependency "rubocop-performance", ">= 1.0.0"
end
