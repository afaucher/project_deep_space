extends SceneTree
func _init():
    var file = FileAccess.open("res://scratch_out.txt", FileAccess.WRITE)
    var f = preload("res://scripts/ships/frigate.gd").new()
    var max_weapon_range = 0.0
    for comp in f.ship_components:
        if comp.get("type") == "weapons" and comp.has("range"):
            max_weapon_range = max(max_weapon_range, comp["range"])
    file.store_string(str("max_weapon_range: ", max_weapon_range))
    file.close()
    quit()
