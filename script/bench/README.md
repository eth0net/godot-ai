# script/bench — GDScript perf microbenchmarks

Fork tooling for substantiating **performance-motivated PRs** with numbers, so a
"this is faster" claim ships as a measured table rather than an argument. The
maintainer hand-benchmarks GDScript perf changes as repo practice (see PRs #743
and #801); including our own benchmark up front matches that bar and de-risks
the review.

> A complexity argument is not a benchmark. #743 was a textbook "two O(depth)
> walks → one" optimization that measured **1.44×–3.31× slower**, because an
> interpreted GDScript loop lost to two native C++ calls. Measure before
> claiming.

## Habit

Include a benchmark with any PR whose motivation is performance (a hot path, an
allocation removed, an algorithmic change). Put the table in the PR description
and the full script + raw output in a collapsed `<details>` block so a reviewer
can reproduce it.

## Usage

1. Copy `_template.gd` to `script/bench/<your-bench>.gd`.
2. Edit **only** the two FILL-IN sections:
   - **candidates** — inline the function bodies you are comparing (baseline
     first). Do *not* preload plugin code; keeping the bench self-contained is
     what lets a reviewer run it with just the one file.
   - **workload / sizes / iters** — a `make_workload(size)` that returns the
     args, the sizes bracketing the real hot-path range, and an iteration count
     high enough that each loop runs for tens of ms.
3. Run headless (no project needed):

   ```
   godot --headless --script script/bench/<your-bench>.gd
   ```

It prints an environment line, a correctness cross-check (**every candidate must
agree before any timing is trusted** — the script exits non-zero on mismatch),
and a Markdown timing table with per-variant µs/call and ratios-vs-baseline.

## Method (what the harness enforces)

- **Correctness gate first.** Cross-check all variants on an edge-case battery;
  a perf change is only "a perf trade" once outputs are proven identical.
- **Warm up, then time** a fixed iteration count with `Time.get_ticks_usec()`,
  across several problem sizes, assigning each result to a sink so the call is
  not optimized away.
- **State the environment** (Godot version, OS, CPU) — the harness prints it.
- **Explain the _why_** in the PR, not just Big-O: GDScript→C++ boundary and
  interpreter cost usually dominate, which is why native engine calls often beat
  a "fewer operations" GDScript rewrite.

The `Callable.callv` indirection the generic harness uses adds a small constant
per call that is equal across variants, so **ratios are unaffected**. If you
need absolute-fidelity per-call numbers, inline direct calls instead.
