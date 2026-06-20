extends SceneTree

func _init():
	var max_radius = 100.0
	var sensor_config = [{
		"id": "dir_high_res",
		"type": "active",
		"active": true,
		"arc_width": PI / 6.0,
		"heading": 0.0
	}]
	var is_ship_oriented = true
	var ship_rot = 0.0

	for i in range(32):
		var a = (i / 32.0) * TAU
		var local_r = 0.0
		
		for s in sensor_config:
			var s_arc = s.get("arc_width", TAU)
			var s_heading = s.get("heading", 0.0)
			if is_ship_oriented:
				s_heading += -PI/2.0
			else:
				s_heading += ship_rot
				
			var diff = abs(wrapf(a - s_heading, -PI, PI))
			if diff <= s_arc / 2.0:
				var s_power = 100.0
				local_r += (s_power / 200.0) * max_radius * (1.0 - diff/(s_arc/2.0))
		
		if local_r > 0:
			print("i=", i, " a=", rad_to_deg(a), " local_r=", local_r, " pos=", Vector2(cos(a), sin(a)))

	quit()
