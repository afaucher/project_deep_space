extends SceneTree

func _init():
	var file = FileAccess.open("res://out.txt", FileAccess.WRITE)
	if file == null:
		print("Failed to open file")
		quit()
		return
		
	var dm = Engine.get_singleton("DialogueManager")
	var resource = load("res://dialogue/characters/aunt_stephanie.dialogue")
	var states = []
	
	file.store_line("--- GETTING GREETING ---")
	var line = await dm.get_next_dialogue_line(resource, "start", states)
	file.store_line("Greeting Text: " + line.text)
	
	file.store_line("--- GETTING REPAIR RESPONSES ---")
	var repairs_resp = null
	for r in line.responses:
		if r.text == "Ask about repairs.":
			repairs_resp = r
			break
			
	var repair_line = await dm.get_next_dialogue_line(resource, repairs_resp.next_id, states)
	file.store_line("Repair Line Text: " + repair_line.text)
	file.store_line("Repair Line Responses Size: " + str(repair_line.responses.size()))
	for r in repair_line.responses:
		file.store_line("  Response: " + r.text + " is_allowed: " + str(r.is_allowed) + " next_id: " + r.next_id)
		
	file.store_line("Repair Line next_id: " + repair_line.next_id)
	
	file.close()
	quit()
