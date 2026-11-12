# frozen_string_literal: true

require_relative 'lib/slopbouncer/version'

Gem::Specification.new do |spec|
  spec.name = 'slopbouncer'
  spec.version = Slopbouncer::VERSION
  spec.summary = 'A stop hook for coding agents that catches weakened tests'
  spec.description = 'When a coding agent is about to finish and has weakened an existing test, Slopbouncer sends ' \
                     'it back once to put the test back or say which behaviour changed. The same check runs as a ' \
                     'plain command in a pipeline, comparing each test before and after a change without running ' \
                     'any code.'
  spec.authors = ['Kipple Pty Ltd']
  spec.homepage = 'https://github.com/mainline-dev/slopbouncer'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*.rb', 'bin/slopbouncer', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.bindir = 'bin'
  spec.executables = ['slopbouncer']

  spec.add_dependency 'prism', '>= 1.5', '< 3'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['homepage_uri'] = 'https://slopbouncer.com'
  spec.metadata['source_code_uri'] = 'https://github.com/mainline-dev/slopbouncer'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/mainline-dev/slopbouncer/issues'
  spec.metadata['changelog_uri'] = 'https://github.com/mainline-dev/slopbouncer/blob/master/CHANGELOG.md'
end
