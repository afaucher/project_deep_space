extends "res://scripts/ships/ship.gd"
class_name SensorDrone

func _init() -> void:
	weapons = {}
	
	max_thrust = 0.0
	max_torque = 0.0
	max_speed = 0.0
	
func _ready() -> void:
	super._ready()
	is_relay = true
	mass = 200.0
	ship_components = [
		{"id": "hull_center", "type": "hull", "rect": Rect2(-10, -10, 20, 20), "health": 200.0, "max_health": 200.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 0.9, "heat": 0.0, "em_emission": 0.0},
		{"id": "hp_sensor_omni", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 50.0, "max_health": 50.0, "density": 0.4, "heat": 0.0, "em_emission": 0.0}
	]
	
	sensor_hardware = [
		{
			"id": "omni_main",
			"type": "active",
			"heading": 0.0,
			"arc_width": TAU,
			"range": 40000.0,
			"resolution": 10.0,
			"health": 100.0,
			"active": true,
			"em_emission": 50.0
		}
	]
