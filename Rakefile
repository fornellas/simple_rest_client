# frozen_string_literal: true
require 'bundler'
Bundler.require

require 'gem_polisher'
GemPolisher.new

desc "Run RSpec"
task :rspec do
  sh 'bundle exec rspec'
end
task test: [:rspec]
