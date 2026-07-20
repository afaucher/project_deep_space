extends SceneTree

func _init():
	print("Start")
	_my_async(1)
	print("End of init")

func _my_async(depth: int):
	print("Depth ", depth, " enter")
	await get_tree().process_frame
	print("Depth ", depth, " after await")
	if depth < 2:
		_my_async(depth + 1)
	print("Depth ", depth, " return")
