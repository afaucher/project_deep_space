extends Node
class_name CommsLedger

var vouched_contacts: Array[NPCProfile] = []
var ephemeral_contacts: Array[NPCProfile] = []

func add_vouched_contact(contact: NPCProfile) -> void:
	if not vouched_contacts.has(contact):
		vouched_contacts.append(contact)

func add_ephemeral_contact(contact: NPCProfile) -> void:
	if not ephemeral_contacts.has(contact):
		ephemeral_contacts.append(contact)

func clear_ephemeral_contacts() -> void:
	ephemeral_contacts.clear()

# Returns all contacts this ledger knows about.
func get_packet_data() -> Dictionary:
	var res = {"vouched": [], "ephemeral": []}
	for npc in vouched_contacts:
		res["vouched"].append({"name": npc.character_name, "faction": npc.faction, "tier": npc.tier, "dialogue_path": npc.default_dialogue.resource_path if npc.default_dialogue else ""})
	for npc in ephemeral_contacts:
		res["ephemeral"].append({"name": npc.character_name, "faction": npc.faction, "tier": npc.tier, "dialogue_path": npc.default_dialogue.resource_path if npc.default_dialogue else ""})
	return res

func get_all_known_contacts() -> Array[NPCProfile]:
	var all_contacts: Array[NPCProfile] = []
	all_contacts.append_array(vouched_contacts)
	all_contacts.append_array(ephemeral_contacts)
	return all_contacts
