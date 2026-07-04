extends SceneTree

func _init():
	print("Starting Dialogue Test...")
	var file_path = "res://dialogue/test.dialogue"
	
	var dialogue_resource = load(file_path)
	print("Dialogue resource loaded: ", dialogue_resource)
	
	# Instantiate Autoload manually for headless SceneTree test
	var dm_script = load("res://addons/dialogue_manager/dialogue_manager.gd")
	var dm = dm_script.new()
	dm.name = "DialogueManager"
	root.add_child(dm)
	print("DialogueManager instantiated.")
		
	var line = await dm.get_next_dialogue_line(dialogue_resource, "start")
	if line != null:
		print("Dialogue line received: ", line.text)
		print("Character: ", line.character)
		for resp in line.responses:
			print("Response: ", resp.text)
	else:
		print("No dialogue line returned.")
		
	print("Test complete.")
	quit(0)
