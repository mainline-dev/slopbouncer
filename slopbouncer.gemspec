# frozen_string_literal: true

require_relative 'lib/slopbouncer/version'

Gem::Specification.new do |spec|
  spec.name = 'slopbouncer'
  spec.version = Slopbouncer::VERSION
  spec.summary = 'Flags tests that got weaker in a change'
  spec.description = 'A static, diff-aware check for code written by coding agents. It compares each test ' \
                     'before and after a change and flags the ones that got weaker, and can tell the agent ' \
                     'that made the change before it finishes.'
  spec.authors = ['Kipple Pty Ltd']
  spec.homepage = 'https://github.com/mainline-dev/slopbouncer'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*.rb', 'bin/slopbouncer', 'LICENSE', 'README.md']
  spec.bindir = 'bin'
  spec.executables = ['slopbouncer']

  spec.add_dependency 'prism', '>= 1.5', '< 3'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
