extends Node

# Autoload singleton: PerfProbe (M45 physics tick performance investigation)
# --------------------------------------------------------------------------
# Tiny tag-based stopwatch for attributing per-frame script cost inside
# _physics_process. Deliberately the simplest possible thing (mirrors
# DebugSettings: extends Node, no class_name -- see CLAUDE.md's headless
# class-cache caveat, referenced globally by the autoload name "PerfProbe").
#
# Usage at a call site (surgical begin/end pairs, no restructuring):
#   PerfProbe.begin("sensor_sweep")
#   ... existing code, unchanged ...
#   PerfProbe.end("sensor_sweep")
#
# `enabled` defaults FALSE. begin()/end() each do exactly one boolean check
# and return when disabled -- this is the "must be nearly free" requirement:
# the probe itself must not become the regression it's built to find. Do NOT
# add any other work (dictionary lookups, Time.get_ticks_usec() calls, etc.)
# ahead of that early-return.
#
# Aggregation is per-tag, bucketed per PHYSICS FRAME (Engine.get_physics_frames())
# so per-frame peaks are visible (a thundering-herd spike averages away over a
# whole run but shows up as max_frame_us). begin/end pairs for a given tag are
# expected to be sequential, not nested/re-entrant (ship A's block finishes
# before ship B's block for the same tag starts within a frame) -- that's how
# every wrapped block in ship.gd/main.gd/beehave_tree.gd is actually called.

var enabled: bool = false

# tag -> { calls, total_us, max_frame_us, _frame_us, _frame_id, _open_us }
var _data: Dictionary = {}

func begin(tag: String) -> void:
	if not enabled:
		return
	var d = _data.get(tag)
	if d == null:
		d = {"calls": 0, "total_us": 0, "max_frame_us": 0, "_frame_us": 0, "_frame_id": -1, "_open_us": 0}
		_data[tag] = d
	var frame_id := Engine.get_physics_frames()
	if d["_frame_id"] != frame_id:
		if d["_frame_us"] > d["max_frame_us"]:
			d["max_frame_us"] = d["_frame_us"]
		d["_frame_us"] = 0
		d["_frame_id"] = frame_id
	d["_open_us"] = Time.get_ticks_usec()

func end(tag: String) -> void:
	if not enabled:
		return
	var d = _data.get(tag)
	if d == null:
		return
	var elapsed: int = Time.get_ticks_usec() - int(d.get("_open_us", 0))
	d["calls"] = int(d["calls"]) + 1
	d["total_us"] = int(d["total_us"]) + elapsed
	d["_frame_us"] = int(d["_frame_us"]) + elapsed

# Clears all aggregated data (NOT the `enabled` flag). Call before a fresh
# measurement window (e.g. after warmup frames) so warmup cost doesn't pollute
# the reported averages.
func reset() -> void:
	_data.clear()

# frame_count: total physics frames in the measurement window, used to compute
# avg_us_per_frame (cost this tag adds to the average tick, INCLUDING frames
# where it didn't fire at all -- e.g. PD only runs when there's ordnance). If
# omitted/<=0, falls back to averaging over calls only (avg_us_per_call basis,
# less useful for tick-budget comparison but still informative).
func report(frame_count: int = 0) -> Dictionary:
	var out := {}
	for tag in _data:
		var d = _data[tag]
		var max_frame_us: int = max(int(d["max_frame_us"]), int(d["_frame_us"]))
		var calls: int = int(d["calls"])
		var total_us: int = int(d["total_us"])
		var avg_us_per_frame: float = (float(total_us) / frame_count) if frame_count > 0 else (float(total_us) / calls if calls > 0 else 0.0)
		out[tag] = {
			"calls": calls,
			"total_us": total_us,
			"avg_us_per_call": (float(total_us) / calls) if calls > 0 else 0.0,
			"avg_us_per_frame": avg_us_per_frame,
			"max_frame_us": max_frame_us,
		}
	return out

# Writes the report as CSV to `path`. Flushes/closes before returning --
# FileAccess.store_line buffers (CLAUDE.md gotcha); a reader immediately after
# would otherwise see zero/partial lines.
func report_csv(path: String, frame_count: int = 0) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("tag,calls,total_us,avg_us_per_call,avg_us_per_frame,max_frame_us")
	var rep := report(frame_count)
	# Rank by avg_us_per_frame descending so the CSV reads top-consumer-first,
	# same as the console table.
	var tags: Array = rep.keys()
	tags.sort_custom(func(a, b): return rep[a]["avg_us_per_frame"] > rep[b]["avg_us_per_frame"])
	for tag in tags:
		var d = rep[tag]
		f.store_line("%s,%d,%d,%.3f,%.3f,%d" % [tag, d["calls"], d["total_us"], d["avg_us_per_call"], d["avg_us_per_frame"], d["max_frame_us"]])
	f.flush()
	f.close()
