# frozen_string_literal: true
require_relative 'lib/simple_rest_client/version'

Gem::Specification.new do |s|
  s.name             = 'simple_rest_client'
  s.version          = SimpleRESTClient::VERSION
  s.summary          = "REST API Client builder"
  s.description      = "Class to aid construction of REST API clients."
  s.authors          = ["Fabio Pugliese Ornellas"]
  s.email            = 'fabio.ornellas@gmail.com'
  s.files            = Dir.glob('lib/**/*').keep_if { |p| !File.directory? p }
  s.extra_rdoc_files = ['README.md']
  s.rdoc_options     = %w(--main README.md lib/ README.md)
  s.homepage         = 'https://github.com/fornellas/simple_rest_client'
  s.license          = 'GPL-3.0'
  s.add_development_dependency 'rake', '~>10.4'
  s.add_development_dependency 'gem_polisher', '~>0.4', '>=0.4.10'
  s.add_development_dependency 'rspec', '~>3.4'
  s.add_development_dependency 'simplecov', '~>0.11', '>=0.11.2'
  s.add_development_dependency 'webmock', '~>1.24', '>=1.24.2'
end
