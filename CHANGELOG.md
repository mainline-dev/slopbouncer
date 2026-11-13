# Changelog

What changed in each version of Slopbouncer.

## Unreleased

- Two tests with the same name in one file are told apart. Before, a change anywhere in such a file reported the first test's assertions as removed.
- A test that was only reformatted is not flagged. Assertions are compared by what they parse to, so quote style, white space and line breaks, parentheses round arguments, a block's braces against `do` and `end`, and a trailing comma no longer count as a change.
- At a terminal, more than 30 findings are shown as a count of each rule in each file. `--all` lists every finding. Piped output and `--json` are complete as before.
- A coding agent is told about the first 20 findings, how many more there are and how to list them all.
- `--help` and `-h` print how to use the command. `--version` and `-v` print the version.
- Run outside a git repository, the command says so in one line. Any other git failure is reported as git's first line of error.
- It runs on Ruby 3.2 and later. Before, it asked for Ruby 3.4.
- Its reports say tests look weaker, where they said tests got weaker. A finding is something to look at, and the tool cannot tell whether the change was intended.

## 0.3.0 - 2026-11-12

- At a terminal the report is grouped by file, with each rule in colour and a count at the end. Sent to a file or another program it stays one plain line for each finding.
- `--color` gives the terminal layout wherever the output goes. `NO_COLOR` keeps the layout and leaves the colour out.
- At a terminal, the command says when no tests got weaker.

## 0.2.0 - 2026-11-12

- Reads RSpec: expectations with their matchers, one-line specs with no name, `:skip` and `:pending` beside a name, `should` and `should_not`, groups with two descriptions, and shared examples.
- A `before`, `after` or `around` hook that makes an assertion is read as a test of its own, and the tests it covers are not reported as asserting nothing.
