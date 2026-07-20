extends SceneTree

func _init():
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/characters/test_hub.dialogue")
	
	print("--- TEST HUB ---")
	var line = await dm.get_next_dialogue_line(resource, "start", [])
	print("Line text: ", line.text)
	print("Line responses count: ", line.responses.size())
	for r in line.responses:
		print("  -> ", r.text)
		
	var opt1_id = line.responses[0].next_id
	var line2 = await dm.get_next_dialogue_line(resource, opt1_id, [])
	print("Line2 text: ", line2.text)
	print("Line2 responses count: ", line2.responses.size())
	for r in line2.responses:
		print("  -> ", r.text)
		
	quit()
