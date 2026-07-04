extends Node

var main
var timer = 0.0

func setup(main_node):
	main = main_node
	# Let's run the campaign bootstrap so there's a world to dump contacts from
	main._bootstrap_campaign()

func _process(delta: float):
	timer += delta
	if timer > 1.0:
		var player = null
		if main.players.has(1):
			player = main.players[1]
			
		var out = FileAccess.open("res://contacts_dump.txt", FileAccess.WRITE)
		if player:
			var contacts = player.active_contacts
			out.store_line("--- DUMPING CONTACTS ---")
			for c_id in contacts:
				var c = contacts[c_id]
				out.store_line("Contact: " + str(c.get("name", "Unknown")) + " at " + str(c.get("pos", Vector2.ZERO)))
			out.store_line("--- END DUMP ---")
			print("[TEST PASSED] Contacts dumped successfully.")
		else:
			out.store_line("Player not found")
			print("[TEST FAILED] Player not found")
		out.close()
		get_tree().quit()
