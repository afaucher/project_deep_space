extends RefCounted
class_name DialogueScratch

# Scratch variable store for .dialogue temporaries.
#
# Dialogue Manager can only ASSIGN (`do x = ...`) to a name that already
# exists on one of the extra_game_states -- an assignment to an unknown name
# raises "Assertion failed: <x> not found" (dialogue_manager.gd's
# show_error_for_missing_state_value) AFTER the right-hand side already
# executed. The failure mode is nasty: the mutation's SIDE EFFECT lands (a
# docking grant is issued, repairs start) but the variable never gets set, so
# every `if`/`elif` on it reads false and the conversation speaks the ELSE
# branch. That is exactly the long-standing "port control says 'Negative, no
# open berths' while the docking indicator appears" bug -- the grant was real,
# the spoken line was not.
#
# Fix: every dialogue-driving caller (comms_panel.gd, tests) appends
# scratch() to its extra_game_states -- a plain Dictionary PRE-DECLARING
# every temporary any .dialogue file assigns. DM finds the key, the
# assignment lands, conditions read the real value.
#
# MAINTENANCE: `do <name> = ...` in ANY dialogue/*.dialogue file requires
# <name> here. Grep: `do \w+ =` across dialogue/. test_port_control_comms'
# out-of-zone check + test_stephanie_dialogue assert on SPOKEN TEXT, so a
# missing key fails loudly in the suite rather than silently in-game.
static func scratch() -> Dictionary:
	return {
		# port_control.dialogue
		"result": {},
		"outcome": "",
		"grant": {},
		"slip": "",
		# characters/aunt_stephanie.dialogue
		"repairs_started": false,
	}
