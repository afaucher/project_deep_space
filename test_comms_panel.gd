extends SceneTree

func _init():
	var file = FileAccess.open("res://out2.txt", FileAccess.WRITE)
	if not file:
		print("Failed to open file")
		quit()
		return
		
	file.store_line("Starting...")
	
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/characters/aunt_stephanie.dialogue")
	
	var states = []
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	
	file.store_line("Line: " + line.text)
	file.store_line("Responses: " + str(line.responses.size()))
	
	var repairs_id = ""
	for r in line.responses:
		if r.text == "Ask about repairs.":
			repairs_id = r.next_id
			break
			
	line = await dm.get_next_dialogue_line(resource, repairs_id, states)
	file.store_line("Line 2: " + line.text)
	file.store_line("Responses: " + str(line.responses.size()))
	file.store_line("Next ID: " + str(line.next_id))
	
	file.close()
	quit()
