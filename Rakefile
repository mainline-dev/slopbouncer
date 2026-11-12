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

# Moves the version on: rake bump:patch, rake bump:minor or rake bump:major.
# It rewrites the number in lib/slopbouncer/version.rb and says which tag to
# push once that is committed.
namespace :bump do
  %i[major minor patch].each_with_index do |part, place|
    desc "Move to the next #{part} version"
    task part do
      file = File.join(__dir__, 'lib/slopbouncer/version.rb')
      source = File.read(file)
      numbers = source[/VERSION = '(\d+\.\d+\.\d+)'/, 1].split('.').map(&:to_i)
      numbers[place] += 1
      version = numbers.fill(0, place + 1).join('.')
      File.write(file, source.sub(/VERSION = '[^']*'/, "VERSION = '#{version}'"))
      puts "Now version #{version}. Commit it, then release with:",
           "  git tag v#{version} && git push origin v#{version}"
    end
  end
end
