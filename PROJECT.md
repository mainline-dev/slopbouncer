Slopbouncer: a static check that flags tests which got weaker.

Purpose
Coding agents make checks pass. One way is to weaken the test.
Slopbouncer reads a change and reports tests that got weaker, so a
person can decide whether that was intended. It is the fast check at
the door. Mutation testing is the slow, thorough one behind it.

Principles
- Static analysis only. It reads code and never runs it.
- Diff-aware. It compares each test before and after the change.
- Tests changing alongside code is normal: that is what test-driven
  development looks like. Adding tests is never flagged.
- It flags for review. It does not block a merge by default.
- It is honest about its limit: it catches tests that are visibly
  weaker. A test that looks thorough and checks nothing needs
  mutation testing.

How it works
1. Ask git which files changed between two commits. Keep test files.
2. Fetch the old and new contents of each (git show base:path,
   git show head:path).
3. Parse both into syntax trees.
4. Reduce each tree to a table of tests: name, assertion count,
   expected values, skip markers.
5. Compare the two tables by test name and report differences.

Rules, first version
- Assertion removed from an existing test.
- Expected value edited in an existing test.
- Assertion count down while the test still exists.
- Test deleted.
- Skip or pending marker added.
- Existing test with zero assertions (basic version; point users to
  their linter's own rule as well).

Rules, later
- New test that would pass against the previous commit's code. This
  needs a test run, so it is an optional pipeline step, not part of
  the static check.
- Scenario or feature files changed by anyone other than their owner.
- Red-before-green record: read a coding agent's run log and report
  whether a failing run of the new test came before a passing one.
- Rows removed from table-driven or parameterised tests.

Known awkward cases
- Renamed tests: match on similar bodies when names differ; use git's
  rename detection for moved files.
- Assertions inside helpers: let a project list its own helper names
  that count as assertions.
- Legitimate removals: a feature deleted along with its tests. This is
  why the default is to flag, not block.

Shape of the first version
- Ruby first, so it can run on Mainline's history. Each added language
  is a short list of what counts as a test and an assertion.
- Interface: a command line. `slopbouncer main..HEAD` prints findings
  and exits non-zero only with a --strict flag.
- No GitHub app, no report format and no second language yet.

Later stages
- TypeScript and Go, and Gherkin step definitions.
- SARIF output, so GitHub shows findings on the changed lines.
- A GitHub Action, then a GitHub app that comments on pull requests.
- A hook for Claude Code and other agents to run it before finishing.

First experiment
Run it across Mainline's own commit history. Record what it flags and
how many flags are false alarms. Write up the result.

Prior art
- Linters already flag empty or skipped tests in one language at a
  time: ESLint's Jest plugin (expect-expect), RuboCop (Minitest and
  RSpec cops), SonarQube, PHPUnit's risky tests. None compare two
  versions of a test.
- ast-grep searches code by structure using tree-sitter with YAML
  rules. Useful for trying out single-file rules. It cannot compare
  versions.
- "Tests as data", Matteo Vaccari, martinfowler.com, November 2026:
  states the problem and proposes protecting test data files.

Repository
- mainline-dev/slopbouncer.
- Licence: MIT.

Working method
One scenario at a time. Write the acceptance scenarios first, for
example "an assertion is removed from an existing test, so it is
flagged" and "a new test is added with new code, so nothing is
flagged". Get them failing before writing code.

