class_name UnitData

extends Object

var name: String = "None"
var role: String = ""
var speed: float = 200.0
var portrait: Texture2D = null
var dialog_lines: Array = []
var inspect_lines: Dictionary = {}  # object_type → Array of lines
var health: float = 100.0
var max_health: float = 100.0
var inventory: Dictionary = {}  # item_name → count

# Equipped gear, keyed by GearDefs slot string ("weapon", "head", "body").
# Empty string = nothing in that slot. Bonuses from equipped items are
# baked into the live stat fields (attack_damage, max_health, speed, …)
# at equip time and reverted at unequip; we only track the slot→item map
# here so the inventory UI can show what's worn.
var equipped: Dictionary = {
	"weapon": "",
	"head":   "",
	"body":   "",
}

# Work-priority scheduler. Each task type has a priority level — higher levels
# are picked first by Main._assign_tasks; ties go to the closest unit. OFF
# means the unit refuses this work entirely. Drafted units skip the queue
# regardless of priorities.
enum Priority { OFF = 0, LOW = 1, MED = 2, HIGH = 3 }
const TASK_TYPES: Array = ["combat", "heal", "repair", "build", "harvest", "mine", "gather"]
var work_priorities: Dictionary = {
	"combat":  Priority.MED,
	"heal":    Priority.MED,
	"repair":  Priority.MED,
	"build":   Priority.MED,
	"harvest": Priority.MED,
	"mine":    Priority.MED,
	"gather":  Priority.MED,
}

# Combat stats — defaults are melee (engineer) values.
var attack_damage: int = 12
var attack_range_tiles: float = 1.2     # how close (in tiles) the unit must be to attack
var attack_cooldown: float = 0.8        # seconds between attacks
var aggro_range_tiles: float = 6.0      # how far the unit auto-detects enemies when drafted
var attack_hit_ratio: float = 0.5       # fraction of attack-anim duration at which damage lands
