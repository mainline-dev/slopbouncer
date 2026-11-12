# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
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
