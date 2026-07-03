extends Node2D
class_name Wormhole

# M16 -- a static cluster landmark: the single exit to the Nexus. For now a
# placed, named marker with a transit stub; actual inter-cluster travel is
# deferred until a second cluster exists (see design_ideas/campaign_spatial_model.md).
#
# Extends Node2D (not a physics hull) -- it's a region marker, not a ship. The
# ClusterManager promotes it as a plain landmark: transform only, no velocity, no
# identity, no AI (see the `is RigidBody2D` guards in cluster_manager.gd).

var landmark_name: String = "Nexus Wormhole"
var nav_radius: float = 4000.0   # approach/transit proximity, used by later nav/transit

# Stub: no destination cluster is charted yet. Returns a status the caller can
# surface to the player; the real transit path lands when Cluster 2 exists.
func attempt_transit(_ship) -> Dictionary:
	return {"ok": false, "reason": "Nexus transit offline -- no charted destination"}
