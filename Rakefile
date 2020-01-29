# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

begin
  require 'rubocop/rake_task'

  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ['-D'] # Rails, display cop name
    task.fail_on_error = true
  end
rescue LoadError
  desc 'rubocop rake task not available (rubocop not installed)'
  task :rubocop do
    abort 'Rubocop rake task is not available. Be sure to install rubocop as a gem or plugin'
  end
end

RSpec::Core::RakeTask.new(:spec)

task default: %i[rubocop spec]
