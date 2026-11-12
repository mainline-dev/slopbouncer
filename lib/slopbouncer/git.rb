# frozen_string_literal: true

require 'open3'

module Slopbouncer
  # What git knows about a change: which files it touched, and what each
  # held before and after.
  module Git
    Changed = Struct.new(:before_path, :after_path, keyword_init: true)

    NOT_A_REPOSITORY = 'Not a git repository. Run it from the root of the repository you want checked.'

    # The files changed between two commits, or between a commit and the
    # working tree when no second commit is given. A file that was added has
    # no before path, and one that was deleted has no after path.
    def self.changed(base, head = nil)
      raise Error, NOT_A_REPOSITORY unless repository?

      run('diff', '--name-status', '-M', *[base, head].compact).lines.map do |line|
        status, first, second = line.chomp.split("\t")
        case status[0]
        when 'A' then Changed.new(after_path: first)
        when 'D' then Changed.new(before_path: first)
        when 'R' then Changed.new(before_path: first, after_path: second)
        else Changed.new(before_path: first, after_path: first)
        end
      end
    end

    # What a file holds at a commit, or in the working tree when none is given.
    def self.show(revision, path)
      revision ? run('show', "#{revision}:#{path}") : File.read(File.join(root, path))
    end

    def self.root
      @root ||= run('rev-parse', '--show-toplevel').strip
    end

    # Outside a repository git answers a diff with its whole help text, so
    # this is asked first.
    def self.repository?
      Open3.capture3('git', 'rev-parse', '--is-inside-work-tree').last.success?
    end

    # When git fails, its first line of error says why. The rest is advice
    # about git's own command line.
    def self.run(*arguments)
      output, error, status = Open3.capture3('git', *arguments)
      raise Error, error.lines.first.to_s.strip unless status.success?

      output
    end
    private_class_method :repository?, :run, :root
  end
end
