class_name GearDefs


# Equipment registry. Each entry binds an inventory item name to a slot,
# the optional role restrictions, and the stat bonuses applied while
# equipped. Stats are added on equip and reverted on unequip via
# Unit.equip_gear / unequip_gear, so existing combat code that reads
# data.attack_damage etc. transparently picks up bonuses without any
# refactor at the read sites.
#
# Slot keys are also the dict keys on UnitData.equipped, so a unit's
# equipped dict looks like { "weapon": "Bone-Hewn Cleaver",
# "head": "Plated Combat Helmet", "body": "Crab Shell Vest" }.


# Slot enum (string-keyed because we serialise these into save data and
# tooltips).
const SLOT_WEAPON: String = "weapon"
const SLOT_HEAD:   String = "head"
const SLOT_BODY:   String = "body"

const SLOTS: Array = [SLOT_WEAPON, SLOT_HEAD, SLOT_BODY]


# Stat bonus keys — names match the corresponding fields on UnitData / Unit
# so equip_gear can apply them with a single setattr-style loop.
#   attack_damage, attack_range_tiles, attack_cooldown, max_health, speed
#
# Restrictions:
#   roles: Array[String] — if present, only listed roles may equip.
#                          Empty / missing = universal.
const DEFS: Dictionary = {
	"Bone-Hewn Cleaver": {
		"slot":   SLOT_WEAPON,
		"sprite": "res://art/items/Bone-Hewn Cleaver.png",
		"roles":  ["Engineer"],
		"stats": {
			"attack_damage":   5,
			"attack_cooldown": -0.2,
		},
		"description": "A brutal melee cleaver fashioned from a Brood Mother fang. Engineer-only.",
	},
	"Salvaged Service Pistol": {
		"slot":   SLOT_WEAPON,
		"sprite": "res://art/items/Salvaged Service Pistol.png",
		"roles":  ["Medic", "Pilot"],
		"stats": {
			"attack_damage":      2,
			"attack_range_tiles": 1.0,
		},
		"description": "A worn but functional sci-fi pistol. Ranged-only.",
	},
	"Bioluminescent Coil Pistol": {
		"slot":   SLOT_WEAPON,
		"sprite": "res://art/items/Bioluminescent Coil Pistol.png",
		"roles":  ["Medic", "Pilot"],
		"stats": {
			"attack_damage":      5,
			"attack_range_tiles": 1.0,
			"attack_cooldown":   -0.3,
		},
		"description": "An advanced pistol fed by a glowing algae coil. Ranged-only.",
	},
	"Plated Combat Helmet": {
		"slot":   SLOT_HEAD,
		"sprite": "res://art/items/Plated Combat Helmet.png",
		"roles":  [],
		"stats": {
			"max_health": 30,
		},
		"description": "A salvaged combat helmet welded from ship-hull plates.",
	},
	"Crab Shell Vest": {
		"slot":   SLOT_BODY,
		"sprite": "res://art/items/Crab Shell Vest.png",
		"roles":  [],
		"stats": {
			"max_health": 20,
		},
		"description": "A protective vest stitched from overlapping crab shells.",
	},
	"Stalker Hide Cloak": {
		"slot":   SLOT_BODY,
		"sprite": "res://art/items/Stalker Hide Cloak.png",
		"roles":  [],
		"stats": {
			"max_health": 15,
			"speed":      20.0,
		},
		"description": "A long survival cloak made from Shore Stalker hide. Lighter than the vest.",
	},
}


# Convenience helpers — keep callers terse.

static func is_gear(item_name: String) -> bool:
	return DEFS.has(item_name)


static func get_def(item_name: String) -> Dictionary:
	return DEFS.get(item_name, {})


static func slot_of(item_name: String) -> String:
	var d: Dictionary = DEFS.get(item_name, {})
	return String(d.get("slot", ""))


# Returns true if the role can equip this gear. Universal items (empty
# roles array or missing key) always return true.
static func role_can_equip(item_name: String, role: String) -> bool:
	var d: Dictionary = DEFS.get(item_name, {})
	if d.is_empty():
		return false
	var roles: Array = d.get("roles", [])
	if roles.is_empty():
		return true
	return roles.has(role)


# Build a one-line stat summary string for tooltips: "+5 dmg, -0.2s CD".
# Uses short labels and signed numbers so each bonus reads as a delta.
static func stat_summary(item_name: String) -> String:
	var d: Dictionary = DEFS.get(item_name, {})
	if d.is_empty():
		return ""
	var stats: Dictionary = d.get("stats", {})
	var parts: Array = []
	for key in stats.keys():
		var v: float = float(stats[key])
		var sign_str: String = "+" if v >= 0.0 else ""
		match key:
			"attack_damage":
				parts.append("%s%d dmg" % [sign_str, int(v)])
			"attack_range_tiles":
				parts.append("%s%.0f range" % [sign_str, v])
			"attack_cooldown":
				parts.append("%s%.1fs CD" % [sign_str, v])
			"max_health":
				parts.append("%s%d HP" % [sign_str, int(v)])
			"speed":
				parts.append("%s%d speed" % [sign_str, int(v)])
			_:
				parts.append("%s%s %s" % [sign_str, str(v), key])
	return ", ".join(parts)
