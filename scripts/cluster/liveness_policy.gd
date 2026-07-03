extends RefCounted
class_name LivenessPolicy

# M14 -- the swappable rule that decides which cluster entities are live. Because
# promotion/demotion is attach/detach on a shared ClusterEntity record (see
# cluster_entity.gd), the "which is live" decision is pure policy and can change
# without touching the plumbing. One configurable object rather than a subclass
# hierarchy -- keeps every caller on the preload-const path (no bare class_name
# reference, per the headless class-cache caveat in CLAUDE.md).
#
#   * BUBBLE    -- live within promote_r; stays live until beyond demote_r
#                  (demote_r > promote_r => hysteresis, no boundary thrash). Default.
#   * FULL_SIM  -- everything live. Small clusters / benchmarks, and the fixture
#                  behavioral tests run under so bubble churn can't perturb them.
#   * DEGRADED  -- live near, a cheap route-tick in a mid-ring, dead-reckon far.
#                  ROUTE_TICK is stubbed as DEAD_RECKON until the traffic-fidelity
#                  work (M20); the mid-ring is that same lever.

enum Mode { BUBBLE, FULL_SIM, DEGRADED }
enum Tier { DEAD_RECKON, ROUTE_TICK, LIVE }

var mode: int = Mode.BUBBLE
var promote_r: float = 45000.0   # BUBBLE
var demote_r: float = 60000.0    # BUBBLE (must be > promote_r)
var near_r: float = 45000.0      # DEGRADED
var far_r: float = 120000.0      # DEGRADED

func configure_bubble(promote_radius: float, demote_radius: float) -> void:
	mode = Mode.BUBBLE
	promote_r = promote_radius
	demote_r = demote_radius

func configure_full_sim() -> void:
	mode = Mode.FULL_SIM

func configure_degraded(near_radius: float, far_radius: float) -> void:
	mode = Mode.DEGRADED
	near_r = near_radius
	far_r = far_radius

# Returns a Tier for this entity given the current viewpoint. `rec` is a
# ClusterEntity (left untyped to avoid coupling; duck-typed on .pos / .is_live()).
func classify(rec, viewpoint: Vector2) -> int:
	match mode:
		Mode.FULL_SIM:
			return Tier.LIVE
		Mode.DEGRADED:
			var dd: float = rec.pos.distance_to(viewpoint)
			if dd <= near_r:
				return Tier.LIVE
			elif dd <= far_r:
				return Tier.ROUTE_TICK
			return Tier.DEAD_RECKON
		_:
			# BUBBLE: an already-live entity survives out to the larger demote_r.
			var d: float = rec.pos.distance_to(viewpoint)
			var threshold: float = demote_r if rec.is_live() else promote_r
			return Tier.LIVE if d <= threshold else Tier.DEAD_RECKON
