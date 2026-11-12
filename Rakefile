# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/test_*.rb'
  t.warning = true
end

task default: :test

# The release workflow runs this first: the tag that started it must name the
# version the gem would be published as.
task :tag_matches_version do
  require_relative 'lib/slopbouncer/version'
  tag = ENV.fetch('GITHUB_REF_NAME')
  next if tag == "v#{Slopbouncer::VERSION}"

  abort "Tag #{tag} does not match the gem, which is version #{Slopbouncer::VERSION}. " \
        "Change lib/slopbouncer/version.rb or tag v#{Slopbouncer::VERSION}."
end
