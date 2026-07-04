extends SceneTree
func _init():
	var uid = ResourceLoader.get_resource_uid("res://icon.svg")
	print(uid)
	print(ResourceUID.id_to_text(uid))
	quit()
