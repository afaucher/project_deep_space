class_name WeaponBehaviorRegistry

const BEHAVIORS = {
	"laser": preload("res://scripts/components/weapons/laser_behavior.gd"),
	"missile": preload("res://scripts/components/weapons/missile_behavior.gd"),
}

static var _instances := {}

static func get_behavior(weapon_type: String):
	if not _instances.has(weapon_type):
		_instances[weapon_type] = BEHAVIORS[weapon_type].new()
	return _instances[weapon_type]
