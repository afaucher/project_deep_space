extends "res://scripts/ships/ship.gd"
class_name Buoy

func _init() -> void:
	ship_tier = ComponentSpec.Tier.STRUCTURE
	max_speed = 0.0
	max_omega = 0.0
	owner_id = 999 # Hostile/Neutral IFF
	
	ship_components = [
		{"id": "hull_port", "type": "hull", "rect": Rect2(-7.5, -7.5, 15.0, 5.0), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		{"id": "hull_stbd", "type": "hull", "rect": Rect2(-7.5, 2.5, 15.0, 5.0), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
		
		# Active face of sensor is at X=-7.5, flush with aft edge.
		{"id": "sensor", "type": "sensors", "rect": Rect2(-7.5, -2.5, 5.0, 5.0), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 50.0, "em_emission": 50.0, "switchable": true, "powered_on": true, "sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 8, "refresh_interval": 1.0, "heading": 0.0, "timer": 0.0},

		
		# Core protected on all sides
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-2.5, -2.5, 5.0, 5.0), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 20.0},
		
		{"id": "hull_fwd", "type": "hull", "rect": Rect2(2.5, -2.5, 5.0, 5.0), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	]
	super()
