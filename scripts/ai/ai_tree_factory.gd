# M12 AI tree factory. Builds the default combat behavior tree in code and returns the
# BeehaveTree node; the caller adds it as a child of the ship (the tree auto-resolves
# its `actor` to its parent on _ready). Scripts are referenced via preload const per the
# project's class-cache convention.
#
# Default tree:
#
#   BeehaveTree
#   └── Selector (RootSelector)
#       ├── Sequence (Disengage)   [highest priority]
#       │   ├── ShouldDisengage    (CONDITION: critically damaged?)
#       │   └── Flee               (run from the nearest hostile)
#       ├── Sequence (Engage)
#       │   ├── AcquireTarget      (FAILURE when nothing hostile is in range)
#       │   ├── SteerToTarget      (posture/range maneuver, SUCCESS each tick)
#       │   └── FireOpportunity    (fire every weapon that bears, SUCCESS each tick)
#       └── Idle                   (coast + hold heading when there is no target)
#
# Leaves return SUCCESS/FAILURE (never RUNNING). The selector tries Disengage first: a
# healthy ship fails its ShouldDisengage condition and falls through to Engage; a hurt
# ship flees and never reaches Engage. Engage runs steer AND fire every tick.
const BeehaveTreeScript = preload("res://addons/beehave/nodes/beehave_tree.gd")
const SelectorScript = preload("res://addons/beehave/nodes/composites/selector.gd")
const SequenceScript = preload("res://addons/beehave/nodes/composites/sequence.gd")
const ShouldDisengageLeaf = preload("res://scripts/ai/leaves/should_disengage_leaf.gd")
const FleeLeaf = preload("res://scripts/ai/leaves/flee_leaf.gd")
const AcquireTargetLeaf = preload("res://scripts/ai/leaves/acquire_target_leaf.gd")
const SteerToTargetLeaf = preload("res://scripts/ai/leaves/steer_to_target_leaf.gd")
const StationSteerToTargetLeaf = preload("res://scripts/ai/leaves/station_steer_to_target_leaf.gd")
const FireOpportunityLeaf = preload("res://scripts/ai/leaves/fire_opportunity_leaf.gd")
const IdleLeaf = preload("res://scripts/ai/leaves/idle_leaf.gd")
const StationKeepingLeaf = preload("res://scripts/ai/leaves/station_keeping_leaf.gd")
const FollowRouteLeaf = preload("res://scripts/ai/leaves/follow_route_leaf.gd")
const CargoRunLeaf = preload("res://scripts/ai/leaves/cargo_run_leaf.gd")
const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")
const ChallengeLeaf = preload("res://scripts/ai/leaves/challenge_leaf.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")

static func build_default() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"

	var root = SelectorScript.new()
	root.name = "RootSelector"
	tree.add_child(root)

	# Disengage (highest priority): break off and run when critically damaged.
	var disengage = SequenceScript.new()
	disengage.name = "Disengage"
	root.add_child(disengage)

	var should_disengage = ShouldDisengageLeaf.new()
	should_disengage.name = "ShouldDisengage"
	disengage.add_child(should_disengage)

	var flee = FleeLeaf.new()
	flee.name = "Flee"
	disengage.add_child(flee)

	var engage = SequenceScript.new()
	engage.name = "Engage"
	root.add_child(engage)

	var acquire = AcquireTargetLeaf.new()
	acquire.name = "AcquireTarget"
	engage.add_child(acquire)

	var steer = SteerToTargetLeaf.new()
	steer.name = "SteerToTarget"
	engage.add_child(steer)

	var fire = FireOpportunityLeaf.new()
	fire.name = "FireOpportunity"
	engage.add_child(fire)

	var idle = IdleLeaf.new()
	idle.name = "Idle"
	root.add_child(idle)

	return tree

# M50 -- pirate tree (design_ideas/jobs_and_itineraries.md /
# implementation_plans/m50_pirate_tree_design.md). Deliberately NO Engage
# branch: a pirate is predatory, not reactive -- it attacks via the job
# (DEMAND/TAKE), never via acquire_target's "shoot any fresh HOSTILE in
# range." Standing gates REACTIVE violence only; the pirate's victims mark IT
# hostile through ordinary witnessed-aggression attribution, not the other
# way around. Disengage still outranks everything -- a crippled pirate flees
# mid-heist because Disengage sits above the runner, not because the heist
# knows about damage (jobs_and_itineraries.md's layering rule).
#
#   Selector
#   |-- Disengage (flee when crippled -- damage outranks the heist)
#   |-- JobRunner (the mission: hunt dark, demand, take, exfil, launder)
#   +-- Idle (no job in either slot -- coast)
static func build_pirate() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"

	var root = SelectorScript.new()
	root.name = "RootSelector"
	tree.add_child(root)

	var disengage = SequenceScript.new()
	disengage.name = "Disengage"
	root.add_child(disengage)
	var should_disengage = ShouldDisengageLeaf.new()
	should_disengage.name = "ShouldDisengage"
	disengage.add_child(should_disengage)
	var flee = FleeLeaf.new()
	flee.name = "Flee"
	disengage.add_child(flee)

	var job_runner = JobRunnerLeaf.new()
	job_runner.name = "JobRunner"
	root.add_child(job_runner)

	var idle2 = IdleLeaf.new()
	idle2.name = "Idle"
	root.add_child(idle2)

	return tree

static func build_station() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"
	
	var root_seq = SequenceScript.new()
	root_seq.name = "RootSequence"
	tree.add_child(root_seq)
	
	var transponder = load("res://scripts/ai/leaves/broadcast_transponder_leaf.gd").new()
	transponder.name = "BroadcastTransponder"
	root_seq.add_child(transponder)

	var root = SelectorScript.new()
	root.name = "ActionSelector"
	root_seq.add_child(root)

	var engage = SequenceScript.new()
	engage.name = "Engage"
	root.add_child(engage)

	var acquire = AcquireTargetLeaf.new()
	acquire.name = "AcquireTarget"
	engage.add_child(acquire)

	var steer_to_target = StationSteerToTargetLeaf.new()
	steer_to_target.name = "StationSteerToTarget"
	engage.add_child(steer_to_target)

	var fire = FireOpportunityLeaf.new()
	fire.name = "FireOpportunity"
	engage.add_child(fire)

	var keep_station_idle = StationKeepingLeaf.new()
	keep_station_idle.name = "StationKeepingIdle"
	root.add_child(keep_station_idle)

	return tree

# M18 patrol tree: same combat priority as the default, but the no-target
# fallback follows the hull's patrol_route (looping) instead of idling. FollowRoute
# fails when there is no route, so a route-less hull still falls through to Idle.
#
# M49 -- Challenge (design_ideas/comms_verbs.md's "Patrol" policy): sits AFTER
# Engage, BEFORE FollowRoute. It always returns FAILURE (cheap side-effect
# work -- DEMAND(IDENTIFY) any fresh UNREPORTED contact in controlled space),
# so it never actually claims the tick; a hostile still preempts everything
# via Engage above it, and with no challenge to send the tree falls straight
# through to FollowRoute exactly as before M49.
#
#   Selector
#   |-- Disengage (flee when crippled)
#   |-- Engage (acquire -> steer -> fire; a hostile preempts the patrol)
#   |-- Challenge (DEMAND(IDENTIFY) UNREPORTED contacts in controlled space; always FAILURE)
#   |-- FollowRoute (cruise the waypoints; SUCCESS while patrolling)
#   +-- Idle (no route -> hold heading)
static func build_patrol() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"

	var root = SelectorScript.new()
	root.name = "RootSelector"
	tree.add_child(root)

	var disengage = SequenceScript.new()
	disengage.name = "Disengage"
	root.add_child(disengage)
	var should_disengage = ShouldDisengageLeaf.new()
	should_disengage.name = "ShouldDisengage"
	disengage.add_child(should_disengage)
	var flee = FleeLeaf.new()
	flee.name = "Flee"
	disengage.add_child(flee)

	var engage = SequenceScript.new()
	engage.name = "Engage"
	root.add_child(engage)
	var acquire = AcquireTargetLeaf.new()
	acquire.name = "AcquireTarget"
	engage.add_child(acquire)
	var steer = SteerToTargetLeaf.new()
	steer.name = "SteerToTarget"
	engage.add_child(steer)
	var fire = FireOpportunityLeaf.new()
	fire.name = "FireOpportunity"
	engage.add_child(fire)

	var challenge = ChallengeLeaf.new()
	challenge.name = "Challenge"
	root.add_child(challenge)

	var patrol = FollowRouteLeaf.new()
	patrol.name = "FollowRoute"
	root.add_child(patrol)

	var idle = IdleLeaf.new()
	idle.name = "Idle"
	root.add_child(idle)

	return tree

# M20 cargo tree: an unarmed hauler. Flees when attacked, otherwise runs its lane
# (CargoRun docks at each station and moves on). No Engage -- civilians don't fight.
#
# M49 -- ThreatResponse (design_ideas/comms_verbs.md's "Cargo/civilian"
# policy): sits between Disengage and CargoRun. Comply-or-run reaction to a
# STOP demand (or holds still, doing nothing, while compelled_stop is
# active -- the ship-level override owns motion). Returns FAILURE when
# there's no incident to react to, so the tree falls through to CargoRun
# exactly as before M49.
#
#   Selector
#   |-- Disengage (flee when crippled/attacked)
#   |-- ThreatResponse (comply-or-run on a STOP demand, always SOS; FAILURE when idle)
#   |-- CargoRun (transit -> dock -> depart around the lane)
#   +-- Idle (no lane -> hold heading)
static func build_cargo() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"

	var root = SelectorScript.new()
	root.name = "RootSelector"
	tree.add_child(root)

	var disengage = SequenceScript.new()
	disengage.name = "Disengage"
	root.add_child(disengage)
	var should_disengage = ShouldDisengageLeaf.new()
	should_disengage.name = "ShouldDisengage"
	disengage.add_child(should_disengage)
	var flee = FleeLeaf.new()
	flee.name = "Flee"
	disengage.add_child(flee)

	var threat_response = ThreatResponseLeaf.new()
	threat_response.name = "ThreatResponse"
	root.add_child(threat_response)

	var cargo = CargoRunLeaf.new()
	cargo.name = "CargoRun"
	root.add_child(cargo)

	var idle = IdleLeaf.new()
	idle.name = "Idle"
	root.add_child(idle)

	return tree
