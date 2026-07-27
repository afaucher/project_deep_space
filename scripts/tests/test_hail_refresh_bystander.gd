extends Node

# Campaign playtest follow-up, 2026-07-27: "we still get duplicate hails
# continuously on campaign start -- every few seconds, maybe 30 in the log."
#
# CAUSE. A demand is heartbeat-kept: JobSteps re-sends it every
# DEMAND_REFRESH_FRAMES (2.0s) under its ORIGINAL seq, and ship.gd's comms
# inbox suppresses those re-assertions so they do not re-alert or spam
# last_hails. But BOTH suppression checks required `addressed_to_me`:
#
#   refreshes_pending -> compares against MY pending_demand
#   refreshes_hold    -> compares against MY compelled_stop
#
# Neither can fire for a bystander, because both compare the hail against the
# receiver's OWN demand state. So every ship within comms range that was not
# the target logged a fresh hail every 2 seconds for the entire life of the
# demand -- ~12 for one 25s interdiction, and a couple running near the player
# at campaign start gives the ~30 that were reported. The block's own comment
# already said a refresh "must not re-alert, re-decide, re-mark, or spam the
# last_hails ring"; the intent simply never reached bystanders.
#
# FIX. Seqs are process-globally monotonic (Hail.hail_seq) and a heartbeat
# deliberately reuses the original, so "have I already heard this exact seq?"
# is exactly "is this a re-assertion?" -- and a bystander CAN ask it.
#
# The bystander is the whole test. The addressed ship was always handled
# correctly, so a test that only checked the target would have passed against
# the bug.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_hail_refresh_bystander

const Frigate = preload("res://scripts/ships/frigate.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const Standing = preload("res://scripts/combat/standing.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make(ship_name: String, owner: int, pos: Vector2) -> Node:
	var s = Frigate.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = ["TEAM_" + ship_name.to_upper()]
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _demand_log_count(observer: Node) -> int:
	var n: int = 0
	for e in observer.eng_log:
		if "DEMAND" in str(e.get("text", "")):
			n += 1
	return n

func setup(main) -> void:
	main_node = main
	print("=== test_hail_refresh_bystander: a demand heartbeat is not a new hail ===")

	# Three ships in mutual comms range: an issuer, its target, and a bystander
	# who is simply nearby -- the player's situation at campaign start.
	var issuer := _make("Issuer", 700, Vector2.ZERO)
	var target := _make("Target", 701, Vector2(2000, 0))
	var bystander := _make("Bystander", 702, Vector2(0, 2000))

	# Let sensors/datalink settle so everyone holds tracks on everyone.
	for i in range(180):
		await main_node.get_tree().physics_frame

	var by_before: int = _demand_log_count(bystander)
	var tgt_before: int = _demand_log_count(target)
	var by_hails_before: int = bystander.last_hails.size()

	# One demand, then heartbeat it the way JobSteps does -- same seq, over and
	# over. Eight refreshes is ~16s of a real interdiction.
	var seq: int = issuer.send_demand(target.get_instance_id(), Hail.RUNG_STOP)
	_assert(seq != -1, "setup: the demand was sent (seq=%d)" % seq)
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame

	const REFRESHES := 8
	for i in range(REFRESHES):
		issuer.refresh_demand(target.get_instance_id(), Hail.RUNG_STOP, seq)
		# A couple of frames is enough for delivery; the real cadence is 2s but
		# the suppression rule is about the SEQ, not about elapsed time, so a
		# tight loop is a strictly harder test than the real one.
		await main_node.get_tree().physics_frame
		await main_node.get_tree().physics_frame

	var by_after: int = _demand_log_count(bystander)
	var tgt_after: int = _demand_log_count(target)

	# THE BUG: one demand, one log entry -- for the bystander too.
	_assert(by_after - by_before <= 1,
		"a BYSTANDER logs the demand ONCE, not once per heartbeat (%d refreshes -> %d new entries)"
			% [REFRESHES, by_after - by_before])
	_assert(by_after - by_before == 1,
		"...and does log it once -- suppression must not swallow the first receipt")

	# The addressed ship was always right; assert it stayed right.
	_assert(tgt_after - tgt_before == 1,
		"the addressed TARGET still logs it exactly once (unchanged behaviour, %d new)"
			% [tgt_after - tgt_before])

	# last_hails is only 8 deep and the comms panel's HAILS section reads it.
	# A hail directed at SOMEONE ELSE can never be rendered there
	# (build_vessel_entries filters on target_iid == my_iid), so it must not
	# occupy a slot at all -- it would push a real, displayable hail out of the
	# ring. Bystander gains ZERO here: the demand was addressed to `target`.
	_assert(bystander.last_hails.size() - by_hails_before == 0,
		"the bystander's ring gains NOTHING for a hail addressed elsewhere -- it could never be displayed, and would evict real history (gained %d)"
			% [bystander.last_hails.size() - by_hails_before])

	# The demand must still be LIVE on the target: suppression changes what gets
	# logged, never whether the demand is honoured. Asserted on pending_demand
	# rather than compelled_stop deliberately -- compelled_stop is the
	# COMPLIANCE state, set when the target's own tree decides to stop, and
	# these fixtures are bare hulls with no AI to comply with. What matters here
	# is that the heartbeat kept the demand alive under its original seq instead
	# of the refresh path dropping or re-creating it.
	_assert(not target.pending_demand.is_empty(),
		"the demand is still live on the target -- refreshes keep it alive, they just stop re-logging")
	_assert(target.pending_demand.get("seq", -1) == seq,
		"...still under the ORIGINAL seq, not replaced by a heartbeat copy")

	# A genuinely NEW demand (fresh seq) must still register everywhere.
	var seq2: int = issuer.send_demand(target.get_instance_id(), Hail.RUNG_IDENTIFY)
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	_assert(seq2 != seq, "setup: the second demand drew a fresh seq")
	_assert(_demand_log_count(bystander) - by_after == 1,
		"a NEW demand still logs for the bystander -- this suppresses repeats, not traffic")

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_hail_refresh_bystander <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_hail_refresh_bystander <<<")
		get_tree().quit(1)
