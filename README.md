# Slopbouncer

A static check that flags tests which got weaker in a change.

A coding agent's job is to make the checks pass. One way to do that is to weaken the check. Slopbouncer compares each test before and after a change and reports the ones that lost something, so a person can decide whether that was intended. It reads code and never runs it, so it takes seconds.

Status: in development. It reads Ruby tests today: Minitest, as `it` blocks or `test_` methods, and RSpec.

## What it flags

| Rule | When |
|---|---|
| `assertion_removed` | An assertion is gone from a test that still exists |
| `expected_value_changed` | The value an assertion expects was edited |
| `test_deleted` | A test, or its whole file, was deleted |
| `skip_added` | A test was marked to be skipped or pending |
| `no_assertions` | A test the change touched asserts nothing |

## What it leaves alone

- New tests added with new code.
- Tests that gained assertions.
- A test that was reworded, moved to another file, or both, with its checks unchanged.
- Files that are not tests.

## Running it

It needs Ruby 3.4 and git.

```shell
gem install slopbouncer
```

Then run it from the root of the repository you want checked:

```shell
slopbouncer main..HEAD
```

The argument is a range of commits. Give one commit instead, such as `HEAD` or `origin/main`, and it checks everything since then, committed or not. At a terminal it lays the findings out by file, with each rule in colour:

```
test/basket_test.rb
  Basket applies a voucher
    skip_added  marked to be skipped

test/checkout_test.rb
  Checkout lets a guest pay
    assertion_removed  assert_equal "paid", order.status

test/refund_test.rb
  Refund refunds part of an order
    expected_value_changed  100 → 90

3 tests got weaker in 3 files
```

When its output goes to a file or another program, it prints one plain line for each finding:

```
test/basket_test.rb: Basket applies a voucher: skip_added: marked to be skipped
test/checkout_test.rb: Checkout lets a guest pay: assertion_removed: assert_equal "paid", order.status
test/refund_test.rb: Refund refunds part of an order: expected_value_changed: 100 → 90
```

| Option | What it does |
|---|---|
| `--json` | Prints the findings as JSON |
| `--strict` | Exits with 1 when anything is flagged |
| `--all` | At a terminal, lists every finding. Without it, more than 30 findings are shown as a count of each rule in each file |
| `--color` | Uses the terminal layout, in colour, wherever the output goes. For a script whose own output a person reads |
| `--agent=NAME` | Runs as that coding agent's hook (see below) |

Setting `NO_COLOR` keeps the terminal layout and leaves the colour out. Without `--strict` it exits with 0 whatever it finds: it flags for review and does not block. It exits with 2 when it is given nothing to compare.

## Feeding it back to a coding agent

Slopbouncer is most use when the agent that made the change hears about it. The agent knows why it changed a test, and it can put the test back.

One command sets an agent up, from the root of your project:

```shell
slopbouncer install claude-code
```

| Agent | Command | What it adds |
|---|---|---|
| Claude Code | `slopbouncer install claude-code` | A `Stop` hook in `.claude/settings.json` |
| Cursor | `slopbouncer install cursor` | A `stop` hook in `.cursor/hooks.json` |
| Gemini CLI | `slopbouncer install gemini` | An `AfterAgent` hook in `.gemini/settings.json` |
| Codex | `slopbouncer install codex` | A `Stop` hook in `.codex/hooks.json` |

It adds one hook and keeps everything else in the file. Running it again changes nothing. For Claude Code, `--local` writes to `.claude/settings.local.json`, which keeps the hook to you and out of the settings your team shares.

When the agent is about to finish and has weakened an existing test, it is sent back once and told which tests (the first 20, and how to list the rest), with two ways to answer: put the test back and make the code pass it, or leave the change and tell the person which behaviour changed. The second time it is let finish, so its reasons are on the record for the person to read.

The hook checks the work the agent has not committed. If your agent commits as it goes, edit the hook's command to name the commit its work started from, such as `origin/main`, in place of `HEAD`.

Codex skips a new hook until you have trusted it: after installing, open `/hooks` in Codex and review it.

Claude Code is the one this has been run under. The Cursor, Gemini CLI and Codex hooks are written to those agents' published hook contracts and tested against them, and have not yet been run inside the agents themselves. If one misbehaves, please open an issue.

An agent set on a passing build can still get round a static check, so keep running the plain command where a person will see it.

## RSpec

An expectation is read whole: its subject, its direction and its matcher. For a plain matcher such as `eq(5)` an edited value shows as `5 → 6`. For a matcher built from several calls, such as `change { total }.by(1)`, the whole matcher is shown before and after.

- A spec with no name, such as `it { is_expected.to be_valid }`, is known by its body.
- `:skip`, `:pending`, `skip: 'reason'` and `pending: 'reason'` beside a spec's or a group's name count as skipping it.
- A `before`, `after` or `around` hook that makes an expectation is read as a test of its own, named after its group. The specs in that group are not reported as asserting nothing.
- `should` and `should_not` are read as expectations too.

## Your own assertion helpers

Slopbouncer counts calls such as `assert_equal`, `refute_nil`, `must_equal` and `expect` as assertions. If your tests assert through helpers of your own, name them in `.slopbouncer.yml` at the root of your repository:

```yaml
assertions:
  - sees_total
  - is_refused
```

A test that only calls helpers Slopbouncer has not been told about looks like a test with no assertions.

## Its limits

- It catches tests that are visibly weaker. A test that looks thorough and checks nothing needs mutation testing, which is slower and runs the code. Use both: Slopbouncer on every change, mutation testing behind it.
- It cannot tell a stronger assertion from a weaker one. An assertion swapped for another kind is reported as removed.
- It compares what assertions parse to, so what a formatter changes is ignored: a string's quote style, white space and line breaks, parentheses round an assertion's arguments, a block's braces against `do` and `end`, a trailing comma. Anything that parses differently is still flagged, including the braces taken from round a trailing hash, as in `eq({ a: 1 })` rewritten as `eq(a: 1)`.
- It reads one file at a time. A check that lives elsewhere, such as an RSpec shared example pulled in with `it_behaves_like`, is not followed, so a test that relies on one can look as if it asserts nothing.
- It cannot see intent. A test changed on purpose, because the behaviour changed, is flagged the same way as one weakened to get a build to pass.

On its first run, over the 706 commits in [Mainline](https://mainline.dev)'s history that touch a test, it flagged 210 of them. In a sample of those, every finding was a real change to a test and every one looked intended. So read a finding as "this test changed in a way worth a look".

## Working on it

```shell
bundle install
bundle exec rake
```

The tests are scenarios. Each one builds a throwaway git repository, makes a change in it, and runs the real command over that change. `PROJECT.md` holds the plan and the rules still to come.

## Releasing

Move the version on with `rake bump:patch`, `rake bump:minor` or `rake bump:major`, and commit. Then tag that commit with the same version and push the tag, as the command tells you:

```shell
git tag v0.2.0 && git push origin v0.2.0
```

GitHub runs the scenarios and publishes the gem to RubyGems. A tag that does not match the version is refused before anything is published.

## Licence

MIT. See `LICENSE`.
