extends SceneTree

## Godot-AI perf microbenchmark template  (fork tooling — see script/bench/README.md)
##
## Copy this file, edit ONLY the two FILL-IN sections, then run headless:
##     godot --headless --script script/bench/<your-bench>.gd
##
## It prints, in order:
##   1. an environment line (Godot version, OS, CPU) to quote in the PR,
##   2. a correctness cross-check — every candidate MUST agree before timing,
##   3. a Markdown timing table, ready to paste into a PR <details> block.
##
## Keep benches self-contained: INLINE the candidate implementations (copy the
## function bodies you are comparing) rather than preloading plugin code. That
## is what lets a reviewer reproduce the numbers with just this one file and no
## project checkout — the same reason the exit code is 1 on a correctness
## mismatch, so a bad bench fails loudly in CI or a shell.
##
## The GENERIC HARNESS section at the bottom travels with every copy; do not
## edit it. Only the two FILL-IN sections change per benchmark.

var _sink: Variant = null  # assigned every iteration so the call is not elided


func _initialize() -> void:
	# =====================================================================
	# FILL-IN 1 — candidates + correctness cases
	# ---------------------------------------------------------------------
	# Every candidate shares one signature. The FIRST entry is the baseline
	# (ratios are computed against it). Prove they agree on an edge-case
	# battery before trusting any timing number.
	var variants := {
		"join": _demo_join,      # baseline (first entry)
		"concat": _demo_concat,
	}
	var cases := [
		{"label": "empty", "args": [0]},
		{"label": "small", "args": [3]},
		{"label": "deep", "args": [30]},
	]

	# =====================================================================
	# FILL-IN 2 — workload + sizes + iteration count
	# ---------------------------------------------------------------------
	# make_workload(size) -> Array of args passed to each candidate in the
	# timed loop. Choose sizes that bracket the real hot-path range, and an
	# iteration count high enough that each loop runs for tens of ms.
	var make_workload := func(size: int) -> Array: return [size]
	var sizes := [3, 10, 30]
	var iters := 100_000

	# ---- run (no need to edit below) ------------------------------------
	print(_env_line("workload size = segment count"))
	print("")
	var agree := _check_agreement(variants, cases)
	print("")
	_run_timings(variants, make_workload, sizes, iters)
	if not agree:
		push_error("candidates disagree — timing is meaningless until they match")
	quit(0 if agree else 1)


# =========================================================================
# FILL-IN candidate implementations (demo — replace with the real A/B/C).
# Inline the bodies you are comparing; do not preload plugin code.
# =========================================================================
func _demo_join(depth: int) -> String:
	var segments: Array[String] = []
	for i in depth:
		segments.append("Child%d" % i)
	return "/Main/" + "/".join(segments) if depth > 0 else "/Main"


func _demo_concat(depth: int) -> String:
	var out := "/Main"
	for i in depth:
		out += "/Child%d" % i
	return out


# =========================================================================
# GENERIC HARNESS — travels with each copy; do not edit.
# =========================================================================
func _env_line(workload_note: String) -> String:
	var v: Dictionary = Engine.get_version_info()
	return "env: Godot %s headless | %s | %s | %s" % [
		v.get("string", "?"),
		OS.get_name(),
		OS.get_processor_name(),
		workload_note,
	]


func _check_agreement(variants: Dictionary, cases: Array) -> bool:
	var names: Array = variants.keys()
	var baseline: String = names[0]
	var all_ok := true
	print("correctness cross-check (baseline = %s):" % baseline)
	for case in cases:
		var args: Array = case["args"]
		var base_val: Variant = (variants[baseline] as Callable).callv(args)
		var row := "  %-12s %s=%s" % [str(case["label"]), baseline, var_to_str(base_val)]
		var ok := true
		for n in names:
			if n == baseline:
				continue
			var val: Variant = (variants[n] as Callable).callv(args)
			row += "  %s=%s" % [n, var_to_str(val)]
			if val != base_val:
				ok = false
		row += "  -> %s" % ("OK" if ok else "MISMATCH")
		if not ok:
			all_ok = false
		print(row)
	print("correctness: %s" % ("ALL AGREE" if all_ok else "MISMATCH FOUND"))
	return all_ok


func _run_timings(variants: Dictionary, make_workload: Callable, sizes: Array, iters: int) -> void:
	var names: Array = variants.keys()
	var baseline: String = names[0]
	var header := "| size |"
	for n in names:
		header += " %s µs/call |" % n
	for n in names:
		if n != baseline:
			header += " %s/%s |" % [n, baseline]
	var col_count := 1 + names.size() + (names.size() - 1)
	print("timing: %d iters per variant per size" % iters)
	print(header)
	print("|" + "---|".repeat(col_count))
	for size in sizes:
		var args: Array = make_workload.call(size)
		var per_call := {}
		for n in names:
			var cb: Callable = variants[n]
			for _w in range(mini(iters / 10, 5000)):  # warmup
				_sink = cb.callv(args)
			var t0 := Time.get_ticks_usec()
			for _i in iters:
				_sink = cb.callv(args)
			per_call[n] = float(Time.get_ticks_usec() - t0) / float(iters)
		var row := "| %s |" % str(size)
		for n in names:
			row += " %.3f |" % float(per_call[n])
		for n in names:
			if n != baseline:
				var base: float = per_call[baseline]
				var ratio := (float(per_call[n]) / base) if base > 0.0 else 0.0
				row += " %.2f× |" % ratio
		print(row)
	print("(µs/call carries a constant Callable.callv overhead, equal across")
	print(" variants, so ratios are unaffected; inline direct calls if you need")
	print(" absolute-fidelity per-call figures.)")
