# M12 AI tree factory. Builds the default combat behavior tree in code and returns the
# BeehaveTree node; the caller adds it as a child of the ship (the tree auto-resolves
# its `actor` to its parent on _ready). Scripts are referenced via preload const per the
# project's class-cache convention.
#
# Default tree (this slice -- M12 minimal engage):
#
#   BeehaveTree
#   └── Selector (RootSelector)
#       ├── Sequence (Engage)
#       │   ├── AcquireTarget    (FAILURE when nothing hostile is in range)
#       │   ├── SteerToTarget    (range-band maneuver, SUCCESS each tick)
#       │   └── FireOpportunity  (fire every weapon that bears, SUCCESS each tick)
#       └── Idle                 (coast + hold heading when there is no target)
#
# Every leaf returns SUCCESS/FAILURE (never RUNNING), so the Engage sequence runs all
# three of its children every tick (steer AND fire), and the selector falls through to
# Idle only when AcquireTarget fails.
const BeehaveTreeScript = preload("res://addons/beehave/nodes/beehave_tree.gd")
const SelectorScript = preload("res://addons/beehave/nodes/composites/selector.gd")
const SequenceScript = preload("res://addons/beehave/nodes/composites/sequence.gd")
const AcquireTargetLeaf = preload("res://scripts/ai/leaves/acquire_target_leaf.gd")
const SteerToTargetLeaf = preload("res://scripts/ai/leaves/steer_to_target_leaf.gd")
const FireOpportunityLeaf = preload("res://scripts/ai/leaves/fire_opportunity_leaf.gd")
const IdleLeaf = preload("res://scripts/ai/leaves/idle_leaf.gd")

static func build_default() -> Node:
	var tree = BeehaveTreeScript.new()
	tree.name = "AITree"

	var root = SelectorScript.new()
	root.name = "RootSelector"
	tree.add_child(root)

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
