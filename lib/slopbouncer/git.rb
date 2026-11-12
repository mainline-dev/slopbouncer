# frozen_string_literal: true

require 'open3'

module Slopbouncer
  # What git knows about a change: which files it touched, and what each
  # held before and after.
  module Git
    Changed = Struct.new(:before_path, :after_path, keyword_init: true)

    # The files changed between two commits. A file that was added has no
    # before path, and one that was deleted has no after path.
    def self.changed(base, head)
      run('diff', '--name-status', '-M', base, head).lines.map do |line|
        status, first, second = line.chomp.split("\t")
        case status[0]
        when 'A' then Changed.new(after_path: first)
        when 'D' then Changed.new(before_path: first)
        when 'R' then Changed.new(before_path: first, after_path: second)
        else Changed.new(before_path: first, after_path: first)
        end
      end
    end

    def self.show(revision, path)
      run('show', "#{revision}:#{path}")
    end

    def self.run(*arguments)
      output, error, status = Open3.capture3('git', *arguments)
      raise Error, "git #{arguments.first} failed: #{error.strip}" unless status.success?

      output
    end
    private_class_method :run
  end
end
