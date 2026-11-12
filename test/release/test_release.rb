# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'yaml'
require_relative '../../lib/slopbouncer/version'

# A version tag pushed to GitHub publishes the gem to RubyGems. The workflow
# signs in as a trusted publisher, so no key is stored anywhere.
describe 'releasing the gem' do
  ROOT = File.expand_path('../..', __dir__)
  RELEASE = File.join(ROOT, '.github/workflows/release.yml')

  def workflow
    YAML.load_file(RELEASE)
  end

  def steps
    workflow.dig('jobs', 'gem', 'steps')
  end

  def position(of)
    steps.index { |step| step.values_at('run', 'uses').compact.any? { |line| line.include?(of) } }
  end

  # What the release workflow runs first, given the tag that started it.
  def check_tag(tag)
    _, error, status = Open3.capture3({ 'GITHUB_REF_NAME' => tag }, 'bundle', 'exec', 'rake', 'tag_matches_version', chdir: ROOT)
    [status.exitstatus, error]
  end

  # YAML reads a bare "on" as true.
  it 'publishes when a version tag is pushed, and at no other time' do
    assert_equal({ 'push' => { 'tags' => ['v*'] } }, workflow[true])
  end

  it 'accepts a tag that names the version being published' do
    assert_equal 0, check_tag("v#{Slopbouncer::VERSION}").first
  end

  it 'refuses a tag that names another version, and says which version the gem is' do
    status, error = check_tag('v99.0.0')

    assert_equal 1, status
    assert_includes error, Slopbouncer::VERSION
  end

  it 'checks the tag and runs the scenarios before it publishes' do
    assert_operator position('rake tag_matches_version'), :<, position('gem push')
    assert_operator position('rake test'), :<, position('gem push')
  end

  it 'signs in to RubyGems as a trusted publisher, with no key stored' do
    assert_equal 'write', workflow.dig('jobs', 'gem', 'permissions', 'id-token')
    assert position('rubygems/configure-rubygems-credentials@')
    refute_includes File.read(RELEASE), 'secrets.'
  end
end

# Moving the version on is one command, so the number is never typed by hand
# and the tag to push is spelled out.
describe 'moving the version on' do
  ROOT_OF_GEM = File.expand_path('../..', __dir__)
  VERSION_FILE = 'lib/slopbouncer/version.rb'

  # A copy of the gem's rake tasks beside a version file of its own, so the
  # real version is left alone.
  before do
    @copy = Dir.mktmpdir('slopbouncer-release')
    FileUtils.mkdir_p(File.join(@copy, File.dirname(VERSION_FILE)))
    FileUtils.cp(File.join(ROOT_OF_GEM, 'Rakefile'), @copy)
    File.write(File.join(@copy, VERSION_FILE), "# frozen_string_literal: true\n\nmodule Slopbouncer\n  VERSION = '1.2.3'\nend\n")
  end

  after { FileUtils.remove_entry(@copy) }

  def rake(task, tag: nil)
    environment = { 'BUNDLE_GEMFILE' => File.join(ROOT_OF_GEM, 'Gemfile'), 'GITHUB_REF_NAME' => tag }
    output, status = Open3.capture2e(environment, 'bundle', 'exec', 'rake', task, chdir: @copy)
    [status.exitstatus, output]
  end

  def version
    File.read(File.join(@copy, VERSION_FILE))[/VERSION = '(.*)'/, 1]
  end

  it 'moves to the next patch version' do
    rake('bump:patch')

    assert_equal '1.2.4', version
  end

  it 'moves to the next minor version, starting its patches again' do
    rake('bump:minor')

    assert_equal '1.3.0', version
  end

  it 'moves to the next major version, starting the rest again' do
    rake('bump:major')

    assert_equal '2.0.0', version
  end

  it 'says which tag to push for the new version' do
    assert_includes rake('bump:minor').last, 'git tag v1.3.0'
  end

  it 'leaves a version the release accepts under that tag' do
    rake('bump:minor')

    assert_equal 0, rake('tag_matches_version', tag: 'v1.3.0').first
  end
end
