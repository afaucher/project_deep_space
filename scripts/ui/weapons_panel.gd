extends PanelContainer
class_name WeaponsPanel

const Standing = preload("res://scripts/combat/standing.gd")

signal fire_weapon_requested(weapon_id: String)
# Post-playtest -- moved here from comms_panel.gd: MARK HOSTILE/UNMARK are a
# targeting-computer judgment call on the LOCKED target, not a comms action.
# c_id is our own track id, same convention comms_panel used; terminal_display
# resolves it to the RPC (mark_contact_hostile/clear_contact_hostile).
signal mark_hostile_requested(c_id: String)
signal unmark_hostile_requested(c_id: String)

const FIRING_FLASH_WINDOW := 0.2 # seconds before cooldown ends where the button reads "* FIRING *" instead of "COOLDOWN"
const SAFETY_FLASH_SECONDS := 1.5 # how long a refused trigger pull stays on the status line

# Closing-rate sample/window sizes for the acceleration readout below --
# matches TimeSeriesGraph's own sample-and-hold pattern, since differentiating
# raw frame-to-frame closing velocity would amplify contact-position jitter
# into a wildly noisy acceleration number.
const CLOSING_VEL_SAMPLE_INTERVAL := 0.2
const CLOSING_ACCEL_WINDOW := 1.0

var current_state: Dictionary = {}
var selected_contact_id: String = ""
var weapon_buttons: Dictionary = {}
var target_info_label: Label
var standing_label: Label
var btn_mark_hostile: Button
var btn_unmark: Button
var weapon_grid: GridContainer
var history_graph: Control
# Weapons safety (playtest B). DEFAULT ENGAGED -- the player disengages it
# deliberately rather than discovering the trigger was already live.
var safety_engaged: bool = true
var safety_check: CheckButton
var safety_status_label: Label
var fire_all_btn: Button
var _safety_flash_t: float = 0.0
var _safety_flash_msg: String = ""
var _closing_vel_samples: Array = [] # [{"t": float, "v": float}, ...]

func _ready() -> void:
	custom_minimum_size = Vector2(460, 200)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.05, 0.8)
	style.border_width_top = 2
	style.border_color = Color.RED
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var title = Label.new()
	title.text = "WEAPONS CONTROL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	weapon_grid = GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(weapon_grid)

	# One button to fire everything that can bear -- mirrors the spacebar / gamepad
	# combat_fire_all action. Sits at the bottom of the weapon list.
	# Weapons safety (playtest B). DEFAULT ENGAGED, explicit and visible --
	# the player disengages it deliberately rather than discovering the trigger
	# was live. Placed directly ABOVE the fire control so the state is in the
	# same glance as the button it governs.
	safety_check = CheckButton.new()
	safety_check.text = "SAFETY"
	safety_check.button_pressed = true
	safety_check.tooltip_text = "Master arm. While engaged, no weapon will fire from this console."
	safety_check.toggled.connect(_on_safety_toggled)
	vbox.add_child(safety_check)

	safety_status_label = Label.new()
	safety_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safety_status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(safety_status_label)

	fire_all_btn = Button.new()
	fire_all_btn.text = "FIRE ALL (Space)"
	fire_all_btn.add_theme_color_override("font_color", Color.RED)
	fire_all_btn.pressed.connect(_fire_all)
	vbox.add_child(fire_all_btn)

	vbox.add_child(HSeparator.new())
	
	var target_label = Label.new()
	target_label.text = "TARGETING COMPUTER"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_color_override("font_color", Color.ORANGE)
	vbox.add_child(target_label)
	
	target_info_label = Label.new()
	target_info_label.text = "NO TARGET LOCKED"
	target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_info_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(target_info_label)

	# Standing metadata + MARK HOSTILE/UNMARK -- moved here from the comms/
	# contacts panels (post-playtest): this is the targeting-computer's own
	# judgment call on whatever it has locked, so it belongs beside the rest
	# of the target readout rather than split across two other panels.
	standing_label = Label.new()
	standing_label.text = ""
	standing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	standing_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(standing_label)

	var standing_hbox = HBoxContainer.new()
	standing_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(standing_hbox)

	btn_mark_hostile = Button.new()
	btn_mark_hostile.text = "MARK HOSTILE"
	btn_mark_hostile.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	btn_mark_hostile.pressed.connect(func(): emit_signal("mark_hostile_requested", selected_contact_id))
	standing_hbox.add_child(btn_mark_hostile)

	btn_unmark = Button.new()
	btn_unmark.text = "UNMARK"
	btn_unmark.pressed.connect(func(): emit_signal("unmark_hostile_requested", selected_contact_id))
	standing_hbox.add_child(btn_unmark)

	var charts_hbox = HBoxContainer.new()
	charts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(charts_hbox)

	# The spider chart (heat/EM/cross-section/density radar) duplicated what
	# this history graph and the text readout below already show -- removed;
	# the graph now takes the freed width. Its HEAT/EM legend (orange/blue,
	# top-left of the plot) is the only heat/EM readout left -- see
	# target_info_label below, which no longer prints those as numbers.
	history_graph = load("res://scripts/ui/timeseries_graph.gd").new()
	history_graph.custom_minimum_size = Vector2(380, 160)
	charts_hbox.add_child(history_graph)
	history_graph.hide()

func _process(delta: float) -> void:
	if _safety_flash_t > 0.0:
		_safety_flash_t = maxf(0.0, _safety_flash_t - delta)
		if _safety_flash_t == 0.0:
			_update_safety_ui()

func _input(event: InputEvent) -> void:
	# combat_fire_all is bound to the gamepad right-trigger AND the spacebar.
	if event.is_action_pressed("combat_fire_all"):
		_fire_all()

func _on_safety_toggled(pressed: bool) -> void:
	safety_engaged = pressed
	_safety_flash_t = 0.0
	_update_safety_ui()

# Keeps the fire controls honest about whether they will actually do anything:
# the FIRE ALL button disables outright when this console cannot fire, and the
# status line always says why. "Disable fire-all when the ship has no weapons"
# (playtest B) is one case of this -- a no-op key reads as broken rather than
# as "you are unarmed" -- so every refusal reason gets the same treatment
# rather than special-casing that one.
func _update_safety_ui() -> void:
	if safety_status_label == null or fire_all_btn == null:
		return
	var refusal: String = _fire_refusal()
	fire_all_btn.disabled = refusal != ""
	# A flash is only valid while it still describes the CURRENT refusal.
	# Otherwise it outlives the situation it reported: pull the trigger on a
	# neutral, then lose the weapon (or the target, or disengage the safety),
	# and the console would keep insisting the target was not flagged. The
	# flash is emphasis on the live reason, never a stale echo of an old one.
	if _safety_flash_t > 0.0 and _safety_flash_msg != refusal:
		_safety_flash_t = 0.0
		_safety_flash_msg = ""
	if _safety_flash_t > 0.0:
		safety_status_label.text = "⚠ " + _safety_flash_msg
		safety_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	elif refusal != "":
		safety_status_label.text = refusal
		safety_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		safety_status_label.text = "ARMED -- WEAPONS FREE"
		safety_status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

# A refused trigger pull has to be VISIBLE, or the safety is indistinguishable
# from a broken control -- the exact complaint behind playtest B's fire-all
# note. Pulling the trigger against the safety flashes the reason.
func _flash_safety(msg: String) -> void:
	_safety_flash_msg = msg
	_safety_flash_t = SAFETY_FLASH_SECONDS
	_update_safety_ui()

func _fire_all() -> void:
	# Request EVERY weapon to fire at the current target. The server gates each shot on
	# target/cooldown/arc/ammo, so weapons that cannot bear simply do nothing -- which is
	# exactly why the player needs no weapon groups, just one "fire all".
	if not current_state.has("weapons"):
		return
	for w_info in current_state["weapons"]:
		_request_fire(w_info.get("id", ""))

# THE SINGLE CHOKE POINT FOR PLAYER-INITIATED FIRE (playtest B, weapons safety).
#
# Every control scheme lands here: the FIRE ALL button, the `combat_fire_all`
# action (spacebar AND gamepad right-trigger, see _input), and each weapon's own
# FIRE button. That last one is why this function exists rather than the checks
# living in _fire_all -- the per-weapon buttons emitted fire_weapon_requested
# DIRECTLY, so a guard on fire-all alone would have left the individual
# hardpoints unguarded, which is exactly the hole this is meant to close. Any
# new binding or button must call this, not emit the signal itself.
#
# This is a CONSOLE INTERLOCK, not an authority check: it is the safety on the
# player's own weapons console. The server still validates everything it always
# did (Ship.fire_weapon's compelled_stop hold, then can_fire's ammo/cooldown/
# power/arc gates) -- nothing here replaces that, and a client cannot grant
# itself a shot by lying, because it can only ever *decline* to send.
func _request_fire(weapon_id: String) -> void:
	if weapon_id == "":
		return
	var refusal: String = _fire_refusal()
	if refusal != "":
		_flash_safety(refusal)
		return
	fire_weapon_requested.emit(weapon_id)

# Why this console will not fire right now -- "" means it will. Returns the
# reason so every refusal can SAY something: a fire control that silently does
# nothing reads as broken, which is the specific complaint behind the
# "disable fire-all when unarmed" note (a no-op key looks like a bug, not like
# "you are unarmed").
func _fire_refusal() -> String:
	if current_state.get("weapons", []).is_empty():
		return "UNARMED -- no weapons fitted"
	if safety_engaged:
		return "SAFETY ENGAGED"
	if selected_contact_id == "":
		return "NO TARGET LOCKED"
	var c: Dictionary = current_state.get("contacts", {}).get(selected_contact_id, {})
	# Wreckage / the honor rule / stale tracks are NOT re-implemented here --
	# Standing.track_engageable_refusal is the same helper AcquireTargetLeaf
	# uses, so the console and the AI cannot disagree about whether there is a
	# real, still-fightable ship there. Those three are mechanical.
	var invalid: String = Standing.track_engageable_refusal(c)
	if invalid != "":
		return invalid
	# ...but WHOSE STANDING we are willing to shoot is policy, and it stays
	# here rather than in the shared helper. This console's policy is "flagged
	# targets only", which is belt-and-braces with the safety switch,
	# deliberately (playtest B): firing on a neutral station is exactly the
	# kind of accident that should be hard to have, especially given A1.
	# HOSTILE is the player's own judgment -- MARK HOSTILE is right there in
	# this panel, and a ship that shoots at you earns it automatically
	# (take_damage posts ASSAULT), so self-defence needs no extra step.
	#
	# ALTERNATIVE, CONSIDERED AND NOT BUILT (2026-07-27): make the safety a
	# real ship property (a master arm) rather than console-only state, so
	# "flagged targets only" is one shared rule and an AI that shoots anybody
	# -- a pirate -- is simply a hull flying with the arm off, instead of a
	# divergent engagement rule. That is a tidier model and probably where this
	# ends up. It was deferred on purpose: it turns a UI fix into an AI-policy
	# change (which hulls fly armed, what a station's arm state means, how it
	# replicates), and the playtest complaint here is specifically that the
	# PLAYER's trigger has no guard. Fix the console first.
	if c.get("standing", "") != Standing.HOSTILE:
		return "TARGET NOT FLAGGED HOSTILE"
	return ""

func _create_weapon_ui(grid: GridContainer, w_id: String, w_name: String) -> void:
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_label = Label.new()
	name_label.text = w_name
	info_vbox.add_child(name_label)
	
	var ammo_label = Label.new()
	ammo_label.text = "Ammo: -- | CD: --"
	ammo_label.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(ammo_label)
	
	grid.add_child(info_vbox)
	
	var fire_btn = Button.new()
	fire_btn.text = "FIRE"
	fire_btn.add_theme_color_override("font_color", Color.RED)
	# Through the choke point, NOT emitting directly -- this button bypassing
	# _fire_all is exactly why _request_fire exists (playtest B).
	fire_btn.pressed.connect(func(): _request_fire(w_id))
	grid.add_child(fire_btn)
	
	weapon_buttons[w_id] = {
		"ammo_label": ammo_label,
		"btn": fire_btn
	}

# Tracks closing_vel in sparse, time-stamped samples and returns the average
# rate of change over CLOSING_ACCEL_WINDOW -- smooths out the jitter that a
# naive frame-to-frame diff of a lerp-smoothed contact velocity would produce.
func _track_closing_accel(closing_vel: float) -> float:
	var now = Time.get_ticks_msec() / 1000.0
	if _closing_vel_samples.is_empty() or now - _closing_vel_samples[-1]["t"] >= CLOSING_VEL_SAMPLE_INTERVAL:
		_closing_vel_samples.append({"t": now, "v": closing_vel})
		var cutoff = now - CLOSING_ACCEL_WINDOW
		while _closing_vel_samples.size() > 1 and _closing_vel_samples[0]["t"] < cutoff:
			_closing_vel_samples.pop_front()

	if _closing_vel_samples.size() < 2:
		return 0.0
	var oldest = _closing_vel_samples[0]
	var newest = _closing_vel_samples[-1]
	var dt = newest["t"] - oldest["t"]
	if dt <= 0.0:
		return 0.0
	return (newest["v"] - oldest["v"]) / dt

func update_data(packet: Dictionary, target_id: String) -> void:
	current_state = packet
	# Switching targets (including to/from "no target") shows a fresh history
	# instead of graphing a mix of two different ships' signatures.
	if target_id != selected_contact_id:
		if is_instance_valid(history_graph):
			history_graph.reset()
		_closing_vel_samples.clear()
	selected_contact_id = target_id

	# Re-evaluate the interlock every packet: the refusal reason depends on the
	# target's live standing, so it has to track selection and standing changes
	# (e.g. MARK HOSTILE arming the console the moment it lands).
	_update_safety_ui()

	if current_state.has("weapons"):
		var weapons = current_state["weapons"] # Array of ship_components weapon entries

		# Generate UI dynamically if not present
		if weapon_buttons.size() == 0:
			for w_info in weapons:
				_create_weapon_ui(weapon_grid, w_info.get("id", ""), w_info.get("id", "").to_upper())

		for w_info in weapons:
			var w_id = w_info.get("id", "")
			if weapon_buttons.has(w_id):
				var is_laser = w_info.get("weapon_type", "") == "laser"
				var ammo = w_info.get("ammo", 0)
				var cd = w_info.get("cooldown", 0.0)

				var lbl = weapon_buttons[w_id]["ammo_label"]
				# Lasers are reactor-powered, not ammo-fed -- no ammo field, no
				# ammo counter (see ship.gd's normalization / weapon_behavior.gd).
				lbl.text = ("CD: %.1f" % cd) if is_laser else ("Ammo: %d | CD: %.1f" % [ammo, cd])

				var btn = weapon_buttons[w_id]["btn"]

				var is_in_arc = false
				var is_in_range = false
				var has_target = false

				var is_powered = true
				var is_alive = true
				if current_state.has("engineering") and current_state["engineering"].has("ship_components"):
					for comp in current_state["engineering"]["ship_components"]:
						if comp.get("id", "") == w_id:
							is_alive = comp.get("health", 0.0) > 0.0
							is_powered = comp.get("powered_on", true)
							break

				if selected_contact_id != "" and current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
					has_target = true
					var c = current_state["contacts"][selected_contact_id]
					var c_pos = c.get("pos", Vector2.ZERO)
					var s_pos = current_state.get("pos", Vector2.ZERO)
					var s_rot = current_state.get("rot", 0.0)

					var w_heading = w_info.get("heading", 0.0)
					var arc_w = w_info.get("arc_width", TAU)
					var w_range = w_info.get("range", 999999.0)

					var dist = s_pos.distance_to(c_pos)
					is_in_range = (dist <= w_range)

					var angle_to = (c_pos - s_pos).angle()
					var weapon_global_heading = s_rot + w_heading
					var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)

					is_in_arc = (abs(rel_angle) <= arc_w / 2.0)

				var range_ok = is_in_range or not is_laser # range only gates lasers -- missiles fly to target regardless of launch distance

				# Single ordered priority list so can_fire and the status text
				# can never disagree about which condition is actually blocking
				# the shot -- each entry is (blocking_condition, display_text).
				var blockers = [
					[not is_alive, "DESTROYED"],
					[not is_powered, "OFFLINE"],
					[not has_target, "NO LOCK"],
					[not is_laser and ammo <= 0, "EMPTY"], # lasers are never ammo-blocked
					[cd > w_info.get("cooldown_max", 1.0) - FIRING_FLASH_WINDOW, "* FIRING *"],
					[cd > 0.0, "COOLDOWN"],
					[not is_in_arc, "OUT OF ARC"],
					[not range_ok, "OUT OF RANGE"],
				]
				var can_fire = true
				var status_text = "FIRE"
				for blocker in blockers:
					if blocker[0]:
						can_fire = false
						status_text = blocker[1]
						break

				btn.disabled = not can_fire
				btn.text = status_text
					
	if selected_contact_id == "":
		target_info_label.text = "NO TARGET LOCKED"
		if is_instance_valid(history_graph): history_graph.hide()
		_update_standing_row({})
	else:
		if current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
			var c = current_state["contacts"][selected_contact_id]
			_update_standing_row(c)
			# c["signature"] is OUR OWN sensors' fused, lerp-smoothed track data
			# (Ship._run_sensor_sweep + the correlation lerp in _physics_process),
			# not the target's actual current_heat/em_signature -- the history
			# graph below is an observed reading too, same as this label.
			var sig = c.get("signature", {"heat": 0.0, "em_noise": 0.0, "cross_section": 1.0, "density": 0.0})
			var speed = c.get("vel", Vector2.ZERO).length()
			var s_pos = current_state.get("pos", Vector2.ZERO)
			var c_pos = c.get("pos", Vector2.ZERO)
			var dist = s_pos.distance_to(c_pos)

			# Closing rate: positive = target getting closer, negative = pulling
			# away. More actionable in combat than either ship's absolute speed.
			var rel_pos = c_pos - s_pos
			var rel_vel = c.get("vel", Vector2.ZERO) - current_state.get("vel", Vector2.ZERO)
			var closing_vel = 0.0
			if rel_pos.length() > 0.001:
				closing_vel = -rel_pos.normalized().dot(rel_vel)
			var closing_accel = _track_closing_accel(closing_vel)

			# Heat/EM dropped from here -- the history graph's own HEAT
			# (orange) / EM (blue) legend is now their only readout.
			target_info_label.text = "Target: %s\nCS: %.1f | Den: %.1f\nDist: %s | Spd: %.1f m/s\nClosing: %.1f m/s | Accel: %.1f m/s^2" % [
				selected_contact_id, sig.get("cross_section", 1.0), sig.get("density", 0.0), Utils.format_dist(dist), speed, closing_vel, closing_accel
			]
			if is_instance_valid(history_graph):
				history_graph.push_sample(sig.get("heat", 0.0), sig.get("em_noise", 0.0))
				history_graph.show()
		else:
			target_info_label.text = "TARGET LOST"
			if is_instance_valid(history_graph): history_graph.hide()
			_update_standing_row({})

# Standing metadata + MARK HOSTILE/UNMARK enablement (moved here from comms_
# panel.gd -- see that file's now-removed _update_action_row() for the rules
# this mirrors). Standing only ever applies to a VESSEL contact (ordnance/
# wreckage/asteroid never carry one, per Standing.compute_standing) --
# no target, or a non-vessel target, disables both buttons; MARK HOSTILE
# disables once already HOSTILE or FRIENDLY (nothing left to declare);
# UNMARK is only meaningful on an already-HOSTILE track.
func _update_standing_row(c: Dictionary) -> void:
	if standing_label == null:
		return
	var classification: String = c.get("classification", "")
	var is_vessel: bool = Standing.is_vessel(classification)
	var standing: String = c.get("standing", "") if is_vessel else ""

	# M52b -- surface the warrant reason behind an escalated standing (e.g.
	# "sustained attack on X", "took cargo", "demanding we stop", or the
	# player's own MARK reason): compute_standing's warrant-index lookup
	# already cache-stamps contact["standing_reason"] with this text
	# (standing.gd/ship.gd), it just had zero UI consumers until now.
	var reason: String = c.get("standing_reason", "") if is_vessel else ""
	if standing == "":
		standing_label.text = ""
	elif reason != "":
		standing_label.text = "Standing: %s -- %s" % [standing, reason]
	else:
		standing_label.text = "Standing: %s" % standing

	# M52 -- SOS as a generic contact attribute (calling session, 2026-07-23,
	# implementation_plans/m52_sos_passive_sync.md): same source
	# contacts_panel.gd's row badge reads (ship.gd's datalink_relay
	# reconciliation, stamped onto a real, already-existing track here since
	# a targetable weapons-panel selection always has one). The targeting
	# computer is exactly where a player checking a locked ship's tactical
	# status would want to know it's calling for help, independent of
	# whatever its standing happens to be.
	var is_sos: bool = c.get("sos", false) if is_vessel else false
	if is_sos:
		var nature: String = c.get("sos_nature", "")
		standing_label.text += "\nSOS: %s" % (nature if nature != "" else "distress call")

	if c.is_empty() or not is_vessel:
		btn_mark_hostile.disabled = true
		btn_unmark.disabled = true
		return

	btn_mark_hostile.disabled = (standing == Standing.HOSTILE or standing == Standing.FRIENDLY)
	btn_unmark.disabled = (standing != Standing.HOSTILE)

