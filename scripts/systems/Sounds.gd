class_name Sounds


# Centralized SFX paths so the wiring sites stay readable
# (`AudioManager.play_2d(Sounds.TREE_FALL, pos)` instead of a raw string)
# and renaming a file means editing one entry here.
#
# Only registered: gathering tier so far. UI / combat / wave SFX get added as
# the user drops files into audio/.

# Loop streams — played continuously while a worker is mid-action. The mp3
# files were authored a few seconds long and just rely on `loop = true` set
# at load time in AudioManager.
const TREE_CHOP_LOOP: String = "res://audio/work/cutting down tree.mp3"
const ROCK_MINE_LOOP: String = "res://audio/work/mine rock.mp3"
const CONSTRUCTION_LOOP: String = "res://audio/work/construction.mp3"

# One-shot fired the moment a Fabricator completes a recipe — separate
# from ITEM_PICKUP because the deposit goes through a different code path
# (Grid._tick_fabricators direct deposit, not gui.notify_loot_batch).
const CRAFT_COMPLETE: String = "res://audio/work/Craft Item Sound  FX By Lux Aeterna Audio.mp3"

# Brood Mother boss growl, fired at her spawn position when the random
# event triggers. Long sample (~10s) so it lingers as the boss stomps
# in toward the base — meant to read as "boss has arrived."
const MONSTER_GROWL: String = "res://audio/creatures/monster growl sound effect.mp3"
# Shorter, sharper predator growl. Plays once per Shore Stalker the moment
# they acquire a target — shifts the engagement from "ambient creature"
# to "actively hunting you."
const BEAST_GROWL: String = "res://audio/creatures/beast growl sound effect.mp3"

# One-shots fired at the moment of an event.
const TREE_FALL: String = "res://audio/work/tree fall.mp3"
const ITEM_PICKUP: String = "res://audio/work/Item Pickup (Item Sound Effect).mp3"

# Combat sounds. Pistol plays as a sustained loop while a ranged unit
# (Medic, Pilot) is engaged; the engineer's melee axe swing is a per-hit
# one-shot since each strike is a discrete swing. Claw hit plays at the
# target's position when a crab's lunge connects (so the impact pans, not
# the attacker).
const PISTOL_SHOT: String = "res://audio/combat/pistol.mp3"
const ENGINEER_MELEE: String = "res://audio/combat/the engineer attacking animation sideways.mp3"
const CLAW_HIT: String = "res://audio/combat/claw hit flesh.mp3"
