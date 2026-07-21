extends SceneTree

## Discovery bench: scene_get_hierarchy walk — current per-node McpScenePath.from_node
## (two native walks up: is_ancestor_of + get_path_to) vs building the path
## incrementally by threading the parent prefix down the DFS (one concat, no walk).
##
## Run: godot --headless --script script/bench/scene_walk.gd
##
## Hypothesis to test, NOT assume: incremental should win on full reads (every
## node emitted) but may lose on deep-paginated reads (it concats every node,
## while from_node only runs for the small in-window set).

var _sink: Variant = null
var _trees := {}  # label -> root Node, cached across sizes, freed at end


func _initialize() -> void:
	# candidates (baseline first)
	var variants := {
		"current": _walk_current,          # from_node per in-window node (baseline)
		"incremental": _walk_incremental,  # prefix threaded down the DFS (always)
		"branched": _walk_branched,        # shipped: incremental iff limit<=0, else current
	}

	# correctness: prove identical output across window/depth/shape before timing
	var c_bushy := _make_bushy(3, 3)
	var c_chain := _make_chain(6)
	var cases := [
		{"label": "bushy full", "args": [c_bushy, 0, 0, 100]},
		{"label": "bushy window", "args": [c_bushy, 5, 10, 100]},
		{"label": "bushy depth-cap", "args": [c_bushy, 0, 0, 2]},
		{"label": "chain full", "args": [c_chain, 0, 0, 100]},
		{"label": "chain window", "args": [c_chain, 2, 2, 100]},
	]

	var make_workload := func(label: String) -> Array: return _scenario_args(label)
	var sizes := [
		"chain-50 full",
		"chain-200 full",
		"bushy-1555 full",
		"bushy-1555 win50@0",
		"bushy-1555 win50@600",
	]
	var iters := 1000

	print(_env_line("scene walk over Node trees; args = [root, offset, limit, max_depth]"))
	print("")
	var agree := _check_agreement(variants, cases)
	print("")
	_run_timings(variants, make_workload, sizes, iters)

	c_bushy.free()
	c_chain.free()
	for k in _trees:
		(_trees[k] as Node).free()
	if not agree:
		push_error("candidates disagree — timing is meaningless until they match")
	quit(0 if agree else 1)


# ------- candidate implementations (inlined; the real handler is scene_handler.gd) -------
func _walk_current(root: Node, offset: int, limit: int, max_depth: int) -> Array:
	var out: Array = []
	var idx: Array[int] = [0]
	_wc(root, out, 0, max_depth, root, offset, limit, idx)
	return out


func _wc(node: Node, out: Array, depth: int, max_depth: int, scene_root: Node, offset: int, limit: int, idx: Array[int]) -> void:
	if depth > max_depth:
		return
	var i: int = idx[0]
	idx[0] = i + 1
	if i >= offset and (limit <= 0 or i < offset + limit):
		out.append({
			"name": node.name,
			"type": node.get_class(),
			"path": _from_node(node, scene_root),
			"children_count": node.get_child_count(),
		})
	for child in node.get_children():
		_wc(child, out, depth + 1, max_depth, scene_root, offset, limit, idx)


func _from_node(node: Node, scene_root: Node) -> String:
	if scene_root == null or node == null:
		return ""
	if node == scene_root:
		return "/" + scene_root.name
	if not scene_root.is_ancestor_of(node):
		return ""
	return "/" + scene_root.name + "/" + str(scene_root.get_path_to(node))


func _walk_incremental(root: Node, offset: int, limit: int, max_depth: int) -> Array:
	var out: Array = []
	var idx: Array[int] = [0]
	_wi(root, "/" + String(root.name), out, 0, max_depth, offset, limit, idx)
	return out


func _walk_branched(root: Node, offset: int, limit: int, max_depth: int) -> Array:
	# Mirrors the shipped scene_handler._walk_tree branch.
	if limit <= 0:
		return _walk_incremental(root, offset, limit, max_depth)
	return _walk_current(root, offset, limit, max_depth)


func _wi(node: Node, node_path: String, out: Array, depth: int, max_depth: int, offset: int, limit: int, idx: Array[int]) -> void:
	if depth > max_depth:
		return
	var i: int = idx[0]
	idx[0] = i + 1
	if i >= offset and (limit <= 0 or i < offset + limit):
		out.append({
			"name": node.name,
			"type": node.get_class(),
			"path": node_path,
			"children_count": node.get_child_count(),
		})
	for child in node.get_children():
		_wi(child, node_path + "/" + String(child.name), out, depth + 1, max_depth, offset, limit, idx)


# ------- fixtures -------
func _make_chain(depth: int) -> Node:
	var root := Node.new()
	root.name = "Main"
	var cur := root
	for i in depth:
		var child := Node.new()
		child.name = "Child%d" % i
		cur.add_child(child)
		cur = child
	return root


func _make_bushy(branch: int, depth: int) -> Node:
	var root := Node.new()
	root.name = "Main"
	_grow(root, branch, depth)
	return root


func _grow(parent: Node, branch: int, depth: int) -> void:
	if depth <= 0:
		return
	for i in branch:
		var child := Node.new()
		child.name = "N%d" % i
		parent.add_child(child)
		_grow(child, branch, depth - 1)


func _scenario_args(label: String) -> Array:
	match label:
		"chain-50 full": return [_tree(label, 50, 0), 0, 0, 1000]
		"chain-200 full": return [_tree(label, 200, 0), 0, 0, 1000]
		"bushy-1555 full": return [_tree(label, 6, 4), 0, 0, 100]
		"bushy-1555 win50@0": return [_tree(label, 6, 4), 0, 50, 100]
		"bushy-1555 win50@600": return [_tree(label, 6, 4), 600, 50, 100]
	return [_tree(label, 3, 3), 0, 0, 100]


func _tree(label: String, a: int, b: int) -> Node:
	if not _trees.has(label):
		_trees[label] = _make_chain(a) if b == 0 else _make_bushy(a, b)
	return _trees[label]


# =========================================================================
# GENERIC HARNESS — copied from _template.gd; do not edit.
# =========================================================================
func _env_line(workload_note: String) -> String:
	var v: Dictionary = Engine.get_version_info()
	return "env: Godot %s headless | %s | %s | %s" % [
		v.get("string", "?"), OS.get_name(), OS.get_processor_name(), workload_note,
	]


func _check_agreement(variants: Dictionary, cases: Array) -> bool:
	var names: Array = variants.keys()
	var baseline: String = names[0]
	var all_ok := true
	print("correctness cross-check (baseline = %s):" % baseline)
	for case in cases:
		var args: Array = case["args"]
		var base_val: Variant = (variants[baseline] as Callable).callv(args)
		var ok := true
		var extra := ""
		for n in names:
			if n == baseline:
				continue
			var val: Variant = (variants[n] as Callable).callv(args)
			if val != base_val:
				ok = false
		extra = "%d nodes" % (base_val as Array).size()
		if not ok:
			all_ok = false
		print("  %-18s %s  -> %s" % [str(case["label"]), extra, "OK" if ok else "MISMATCH"])
	print("correctness: %s" % ("ALL AGREE" if all_ok else "MISMATCH FOUND"))
	return all_ok


func _run_timings(variants: Dictionary, make_workload: Callable, sizes: Array, iters: int) -> void:
	var names: Array = variants.keys()
	var baseline: String = names[0]
	var header := "| scenario |"
	for n in names:
		header += " %s µs/call |" % n
	for n in names:
		if n != baseline:
			header += " %s/%s |" % [n, baseline]
	var col_count := 1 + names.size() + (names.size() - 1)
	print("timing: %d iters per variant per scenario" % iters)
	print(header)
	print("|" + "---|".repeat(col_count))
	for size in sizes:
		var args: Array = make_workload.call(size)
		var per_call := {}
		for n in names:
			var cb: Callable = variants[n]
			for _w in range(mini(iters / 10, 5000)):
				_sink = cb.callv(args)
			var t0 := Time.get_ticks_usec()
			for _i in iters:
				_sink = cb.callv(args)
			per_call[n] = float(Time.get_ticks_usec() - t0) / float(iters)
		var row := "| %s |" % str(size)
		for n in names:
			row += " %.2f |" % float(per_call[n])
		for n in names:
			if n != baseline:
				var base: float = per_call[baseline]
				row += " %.2f× |" % ((float(per_call[n]) / base) if base > 0.0 else 0.0)
		print(row)
