extends Node

var comms
var dm

func _ready():
	comms = load("res://scripts/ui/comms_panel.gd").new()
	add_child(comms)
	
	comms.chat_log = RichTextLabel.new()
	comms.chat_header = Label.new()
	comms.responses_vbox = VBoxContainer.new()
	comms.active_dialogue_resource = load("res://dialogue/characters/aunt_stephanie.dialogue")
	
	# Fake player/station
	comms.active_chat_source_id = 1
	var dummy_station = Node2D.new()
	dummy_station.name = "Station"
	dummy_station.set_meta("available_npcs", [])
	
	print("Calling process dialogue...")
	comms._process_dialogue("start")
	await get_tree().create_timer(1.0).timeout
	print("Calling it again to simulate picking a choice...")
	comms._process_dialogue("28") # node ID for repairs refusal
	await get_tree().create_timer(1.0).timeout
	print("Done")
	quit()
