class_name CreatureDefs

# Creature roster for the wave-defense system. Each def carries:
# - name: display string (for HUD / debug)
# - tex_down / tex_side: sprite paths. tex_down is used for vertical movement
#   (north + south), tex_side for horizontal (flipped horizontally per direction).
# - flip_v_south: true if tex_down shows the creature facing NORTH (e.g., our
#   "facing up" sprites) — the renderer flips it vertically when moving south.
#   False if tex_down already faces south (no flip needed; tide crawler).
# - hp, speed, attack_damage, attack_cooldown, attack_range_tiles: combat stats.
# - drops: optional Array of { item, min, max, chance } entries. On kill, each
#   entry rolls independently — chance gates whether it drops at all, then
#   randi_range(min, max) rolls the count. Items auto-deposit to the closest
#   live unit (shared inventory pool, so it's effectively team-wide).
#
# Wave compositions in WaveManager pick from these keys.
const DEFS: Dictionary = {
	"alien_crab": {
		"name": "Alien Crab",
		"tex_down": "res://art/enemies/alien crab facing up.png",
		"tex_side": "res://art/enemies/alien crab sideway facing left.png",
		"flip_v_south": true,
		"hp": 30,
		"speed": 60.0,
		"attack_damage": 7,
		"attack_cooldown": 1.4,
		"attack_range_tiles": 0.9,
		"render_scale": 0.7,
		"drops": [
			{"item": "Crab Shell", "min": 1, "max": 2, "chance": 1.0},
		],
	},
	"tide_crawler": {
		"name": "Tide Crawler",
		"tex_down": "res://art/enemies/tide crawler facing down.png",
		"tex_side": "res://art/enemies/tide crawler facing left.png",
		"flip_v_south": false,
		"hp": 45,
		"speed": 75.0,
		"attack_damage": 9,
		"attack_cooldown": 1.4,
		"attack_range_tiles": 0.9,
		"drops": [
			{"item": "Crawler Hide", "min": 1, "max": 2, "chance": 1.0},
			{"item": "Bioluminescent Algae", "min": 1, "max": 1, "chance": 0.3},
		],
	},
	"shore_stalker": {
		"name": "Shore Stalker",
		"tex_down": "res://art/enemies/shore stalker facing up.png",
		"tex_side": "res://art/enemies/shore stalker facing left.png",
		"flip_v_south": true,
		"hp": 25,
		"speed": 110.0,
		"attack_damage": 12,
		"attack_cooldown": 1.0,
		"attack_range_tiles": 1.0,
		# Predator growl, fired once when the stalker acquires a target.
		# Crab.gd reads this and plays the one-shot at the creature's
		# position; an empty / missing field disables the cue.
		"growl_sound": "res://audio/creatures/beast growl sound effect.mp3",
		"drops": [
			{"item": "Stalker Fang", "min": 1, "max": 1, "chance": 1.0},
			{"item": "Crab Shell", "min": 1, "max": 1, "chance": 0.4},
		],
	},
	"sky_mawling": {
		"name": "Sky Mawling",
		"tex_down": "res://art/enemies/sky mawling facing up.png",
		"tex_side": "res://art/enemies/sky mawling facing left.png",
		"flip_v_south": true,
		"hp": 18,
		"speed": 135.0,
		"attack_damage": 6,
		"attack_cooldown": 0.9,
		"attack_range_tiles": 0.9,
		"drops": [
			{"item": "Mawling Wing", "min": 1, "max": 1, "chance": 1.0},
		],
	},
	# Boss-tier ambush creature used by the Brood Mother random event. Slow,
	# high HP, devastating attack — players are meant to draft + focus-fire.
	# render_scale stretches the in-world sprite past the default 1-tile
	# width so the creature reads as a real boss instead of an oversized crab.
	"brood_mother": {
		"name": "Brood Mother",
		"tex_down": "res://art/enemies/broodmother facing up.png",
		"tex_side": "res://art/enemies/broodmother sideway facing left.png",
		"flip_v_south": true,
		"hp": 340,
		"speed": 50.0,
		"attack_damage": 22,
		"attack_cooldown": 1.4,
		"attack_range_tiles": 1.4,
		"render_scale": 3.0,
		"drops": [
			{"item": "Stalker Fang", "min": 3, "max": 5, "chance": 1.0},
			{"item": "Crawler Hide", "min": 2, "max": 4, "chance": 1.0},
			{"item": "Strange Egg",  "min": 2, "max": 3, "chance": 1.0},
			{"item": "Bioluminescent Algae", "min": 3, "max": 5, "chance": 1.0},
		],
	},
}
