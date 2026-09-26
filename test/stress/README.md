# Stress tier

Fourteen generators build random schemas and programs, run them through
`produce`, `pre_produce`, `exec` and `pre_exec`, and classify the outcome
of every step; three exhaustive oracles check the ordering of trait reads
against an independent model. Two things make the generators useful:

* an absolute check: no outcome may belong to an alarming class (see
  `SeedFactory.StressOutcomes`): a hang, a requested entity or trait
  silently missing afterwards, a requested entity produced by `pre_produce`,
  or a raw crash from inside the planner (`KeyError`, `FunctionClauseError`,
  `MatchError`, `BadMapError`). Loud `SeedFactory` exceptions are legitimate
  outcomes for unsatisfiable programs;
* a differential check: the same generator run on two checkouts produces two
  dumps, and the classifier lists every seed whose outcome changed.

Each generator is a test module tagged `:stress`, excluded from the default
run. Its header describes the dimension it covers.

## Running

```sh
mix test --only stress                                   # the whole tier
mix test --only stress test/stress/stress_traits_dump_test.exs
STRESS_N=3000 mix test --only stress --timeout 600000 test/stress/stress_traits_dump_test.exs
```

`STRESS_N` sets the number of seeds (the defaults are 400, or 150 for the
multi-step generators). Above about 800 seeds a run outgrows the default
60-second test timeout, hence `--timeout`. Every schema is generated from its
seed deterministically, so a seed number identifies the same schema on every
machine and in every checkout that carries the same generator.

## Dumps and the differential comparison

```sh
STRESS_OUT=/tmp/main_traits.bin mix test --only stress test/stress/stress_traits_dump_test.exs
```

writes a dump: a map from seed to the generated schema, the program, the
outcome(s) and the generated source. Two dumps of one generator are compared
with

```sh
MIX_ENV=test mix run test/stress/scripts/classify.exs /tmp/old_traits.bin /tmp/main_traits.bin
```

which prints the frequency of every outcome transition at the first diverging
step, then the suspicious rows: an `:ok` that turned into a failure, or a new
outcome that is neither `:ok` nor a loud exception. A seed is inspected with

```sh
MIX_ENV=test mix run test/stress/scripts/show_seed.exs /tmp/main_traits.bin 293
```

which prints the request, the steps, the outcome and the schema source, ready
to be pasted into a test.

To compare against a previous release, run the generator in a checkout of
that release:

```sh
git worktree add ../seed_factory-previous <tag>
mkdir -p ../seed_factory-previous/stress
cp test/stress/stress_traits_dump_test.exs ../seed_factory-previous/stress/
cp test/support/stress_outcomes.ex ../seed_factory-previous/test/support/
cd ../seed_factory-previous
STRESS_OUT=/tmp/old_traits.bin mix test --timeout 600000 stress/stress_traits_dump_test.exs
```

A checkout older than the tier does not exclude the `:stress` tag, so the
file runs as a plain test there; a newer one needs `--only stress`. The
`STRESS_N` of both runs must match.

## Reading the differences

Not every changed outcome is a finding. Classes accepted knowingly:

* a loud exception of a different class on both sides, or `:ok` on the new
  side where the old side failed;
* a multi-step program whose early step chose a valid plan the old core also
  had, and whose later step then cannot be satisfied on that context while it
  can on a fresh one: the early step cannot foresee a later request;
* a requested entity the old core let a deleting command consume: the new
  core refuses such a plan, since every requested entity sits in the final
  context;
* a plan of a different shape where both sides succeed, such as another
  command producing a side entity.

What matters is a new `:ok → raise` class, or any alarming outcome on the new
side.

## The ordering oracle

`ordering_oracle_test.exs` is not random. Four commands update one entity
carrying two traits, each command may demand any subset of the two traits,
and the test builds all 256 such schemas. For every schema an independent
model walks the 24 execution orders and decides whether one satisfies every
demand; `produce` is then asked for the four outputs in all 24 request orders
and has to find a plan exactly when the model says one exists, or refuse
before any resolver runs. Unlike the generators, it proves the search
complete on this shape: a refusal it accepts is a refusal the model confirms.
Its scope is the ordering of reads and losses of traits; deleting commands,
re-producers and alternative producers are outside it.

`conditional_ordering_oracle_test.exs` repeats the model with one re-applier
declared under an `args_pattern` over a generated param, built once with the
generator returning true and once false: 512 schemas, each requested in the
forward and the reverse order of its outputs. The search cannot judge that
declaration, so the test proves that the prediction before the consumer's
step, with the generated value fixed, agrees with the model exactly where the
search alone cannot.

`dependent_ordering_oracle_test.exs` adds dependencies: every command may
require the output of one other command, so a reader can be forced after the
command stripping its trait and the plan has to shelter it, with a certain
re-applier or a conditional one. The model checks the dependencies along with
the traits. By default one command demands traits and the family is
exhaustive over the acyclic dependency patterns and both generator values
(416 schemas); `ORACLE_FULL=1` runs every demand combination, tens of
thousands of schemas, for a long local run.

## Adding a generator

* Seed the random generator from the case seed (`:rand.seed(:exsss, {...})`)
  and draw everything from it, so a seed reproduces its schema. Once a
  generator has been used for a differential, do not remove or reorder a
  random draw: every seed would change meaning. Prefix a draw that turns out
  unused with an underscore instead.
* Build the schema module with `Code.compile_string`, rescue
  `Spark.Error.DslError` and skip the case, so the DSL validations decide what
  a legal schema is.
* Record `outcome` (or a list `outcomes` for multi-step programs), the
  request or `steps`, and the generated `source`, so `classify.exs` and
  `show_seed.exs` work unchanged.
* Run each program in a task with a timeout, so a hang becomes an outcome
  instead of a stuck run.
* End the test with `assert SeedFactory.StressOutcomes.alarming(results) == []`.
* Reach for a targeted sub-generator when a shape is too rare to appear by
  chance: `stress_args_pattern_dump_test.exs` dedicates a third of its
  programs to one such shape.
