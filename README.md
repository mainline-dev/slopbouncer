# Slopbouncer

A static check that flags tests which got weaker in a change.

A coding agent's job is to make the checks pass. One way to do that is to weaken the check. Slopbouncer compares each test before and after a change and reports the ones that lost something, so a person can decide whether that was intended. It reads code and never runs it, so it takes seconds.

Status: in development. It reads Ruby tests today (Minitest, as `it` blocks or `test_` methods).

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

It needs Ruby 3.4 and git. There is no gem yet, so clone it and run the command from the root of the repository you want checked:

```shell
git clone https://github.com/mainline-dev/slopbouncer.git
cd your-project
ruby ../slopbouncer/bin/slopbouncer main..HEAD
```

The argument is a range of commits. It prints one line for each finding:

```
test/basket_test.rb: Basket applies a voucher: skip_added: marked to be skipped
test/checkout_test.rb: Checkout lets a guest pay: assertion_removed: assert_equal "paid", order.status
test/refund_test.rb: Refund refunds part of an order: expected_value_changed: 100 → 90
```

| Option | What it does |
|---|---|
| `--json` | Prints the findings as JSON |
| `--strict` | Exits with 1 when anything is flagged |

Without `--strict` it exits with 0 whatever it finds: it flags for review and does not block. It exits with 2 when it is not given a range.

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
- It cannot see intent. A test changed on purpose, because the behaviour changed, is flagged the same way as one weakened to get a build to pass.

On its first run, over the 706 commits in [Mainline](https://mainline.dev)'s history that touch a test, it flagged 210 of them. In a sample of those, every finding was a real change to a test and every one looked intended. So read a finding as "this test changed in a way worth a look".

## Working on it

```shell
bundle install
bundle exec rake
```

The tests are scenarios. Each one builds a throwaway git repository, makes a change in it, and runs the real command over that change. `PROJECT.md` holds the plan and the rules still to come.

## Licence

MIT. See `LICENSE`.
