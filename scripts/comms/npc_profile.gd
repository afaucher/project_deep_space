extends Resource
class_name NPCProfile

enum Tier {
	PUBLIC,
	EPHEMERAL,
	VOUCHED
}

@export var character_name: String = "Unknown Contact"
@export var faction: String = "Independent"
@export var tier: Tier = Tier.PUBLIC
@export var default_dialogue: Resource # the DialogueResource
