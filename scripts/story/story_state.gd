extends Node

# M39 -- Story state: flags + quest items that outlive a single conversation
# ("mission accepted", "todd_found", "has present"). Dialogue conditions read
# them (`if story.has_flag(...)`); dialogue mutations write them
# (`do story.set_flag(...)`). See implementation_plans/m39_m44_homefront_roadmap.md,
# "Story data architecture" + "Significant challenges" #4 (no save system yet,
# but everything here must be plain-serializable so a save file later is a
# `var_to_str` away).
#
# PLAIN DATA ONLY. Never store an Object/Node/Resource reference in flags or
# quest_items -- that's the save-system boundary this autoload deliberately
# sits behind (see the roadmap's challenge #1 and #4). Keep this dead simple:
# no signals, no derived state, just two dictionaries and narrow accessors.

var flags: Dictionary = {}
var quest_items: Dictionary = {}

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true

func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)

func clear_flag(flag_name: String) -> void:
	flags.erase(flag_name)

func grant_item(id: String) -> void:
	quest_items[id] = true

func has_item(id: String) -> bool:
	return quest_items.get(id, false)

func remove_item(id: String) -> void:
	quest_items.erase(id)

# Test-only reset -- clears all story state between test cases so a mission
# started/flag set in one scenario can't bleed into the next (StoryState is a
# process-wide autoload singleton, so state otherwise persists across an
# entire test run).
func reset() -> void:
	flags.clear()
	quest_items.clear()
