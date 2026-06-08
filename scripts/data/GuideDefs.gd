class_name GuideDefs


# Player-facing item glossary. Each entry is a hand-written description +
# a list of acquisition sources. The Guide tab in the bottom button row
# renders these so a new player can answer "where do I get X?" without
# having to scour the world.
#
# Entries should match the keys in GUI.ITEM_ICONS so the icon shows up
# automatically. New items added to ITEM_ICONS without an entry here
# fall back to a generic "Drops in the world." description, but the
# search list still indexes them — it's worth keeping this in sync as
# the roster grows.
const ENTRIES: Dictionary = {
	# ── Raw resources ───────────────────────────────────────────────────────
	"Driftwood Piece": {
		"description": "Salt-bleached wood washed up on the shore. Burns clean and bends when heated. The most basic building material.",
		"sources": [
			"Chop trees (3x3 footprint)",
			"Pick up driftwood piles scattered along the coast",
			"Hunt Driftbacks — slow grazers loitering by the driftwood piles (1-3)",
		],
	},
	"Fiber": {
		"description": "Tough plant cordage harvested from alien tree bark. Used in armor stitching, bandages, and rope.",
		"sources": [
			"Drops occasionally from chopped trees",
		],
	},
	"Bioluminescent Algae": {
		"description": "A glowing teal slime that pulses with weak light. Volatile under heat but stable when contained.",
		"sources": [
			"Drops occasionally from chopped trees",
			"Drops sometimes from Tide Crawler kills",
			"Brood Mother always drops 2-4",
		],
	},
	"Stone": {
		"description": "Dense rock chunks from the alien crust. Heavy, durable — the backbone of late-game walls.",
		"sources": [
			"Mine rocks (any rock cluster)",
		],
	},
	"Iron Chunk": {
		"description": "Raw iron ore. Has to be refined at a Fabricator before it's useful for anything.",
		"sources": [
			"Mine rocks (small chance)",
			"Mine iron ore veins (always)",
		],
	},
	"Copper Nugget": {
		"description": "Native copper, soft and conductive. Refined into Electronics at the Fabricator.",
		"sources": [
			"Mine rocks (small chance)",
			"Mine copper ore veins (always)",
		],
	},
	"Sand Glass Shard": {
		"description": "Naturally-formed glass from sand vitrified by lightning strikes. Used in optics and electronics.",
		"sources": [
			"Mine rocks (small chance)",
		],
	},
	# ── Creature drops ──────────────────────────────────────────────────────
	"Crab Shell": {
		"description": "Hardened chitin plates from native crustaceans. Light enough for armor, tough enough to deflect a fang.",
		"sources": [
			"Always drops from Alien Crabs (1-2)",
			"Occasional drop from Shore Stalker kills",
		],
	},
	"Crawler Hide": {
		"description": "Mottled, flexible hide from a Tide Crawler. Resists damp better than crab shell, useful for cloaks and gloves.",
		"sources": [
			"Always drops from Tide Crawlers (1-2)",
			"Drops 2-3 from Brood Mother",
		],
	},
	"Stalker Fang": {
		"description": "Curved tooth from an ambush predator. The barbs make it ideal for puncturing tough armor.",
		"sources": [
			"Always drops from Shore Stalkers (1)",
			"Brood Mother drops 2-4",
		],
	},
	"Mawling Wing": {
		"description": "Translucent membrane from a Sky Mawling. Lighter than fiber, used in advanced gear (no recipes yet).",
		"sources": [
			"Always drops from Sky Mawlings (1)",
		],
	},
	"Strange Egg": {
		"description": "An iridescent egg with a slow heartbeat inside. Studied as a curiosity — also a key crafting reagent.",
		"sources": [
			"Drops from Brood Mother (1-2)",
			"Glowing Egg Cluster choice event (collect option)",
		],
	},
	"Alien Shell": {
		"description": "An unusual shell with chitin plating beyond what a normal crab grows. Decorative.",
		"sources": [
			"Rare loot — not actively dropped by current creatures",
		],
	},
	# ── Crafted goods (require Fabricator) ──────────────────────────────────
	"Metal Scrap": {
		"description": "Refined metal ready for construction and weapons. The bottleneck for most builds.",
		"sources": [
			"Loot the crashed ship and supply crates",
			"Fabricator: Refine 3 Iron Chunk → 1 Metal Scrap (8s)",
			"Supply Drop event",
		],
	},
	"Electronics": {
		"description": "Hand-soldered circuitry. Required for the Fabricator itself and every electronic structure.",
		"sources": [
			"Loot the crashed ship and supply crates",
			"Fabricator: 2 Copper + 1 Glass Shard → 1 Electronics (12s)",
			"Supply Drop event",
		],
	},
	"Bandages": {
		"description": "Rolls of clean dressing. Used by medics in the field.",
		"sources": [
			"Loot the crashed ship and supply crates",
			"Fabricator: 2 Fiber + 1 Algae → 1 Bandages (6s)",
		],
	},
	"Medical Supplies": {
		"description": "A complete medkit — antiseptic, gauze, suture kit. Heals more than bandages alone.",
		"sources": [
			"Loot the crashed ship and supply crates",
			"Fabricator: 1 Algae + 1 Crab Shell + 2 Fiber → 1 Medical Supplies (15s)",
		],
	},
	"Rations": {
		"description": "Field rations of whatever the alien fauna will tolerate. Doesn't have a use yet — flavor item.",
		"sources": [
			"Loot the crashed ship and supply crates",
			"Fabricator: 1 Crab Shell + 1 Strange Egg → 2 Rations (10s)",
		],
	},
	"Tools": {
		"description": "Wrench-and-driver kit. Cosmetic loot pulled from the wreckage; not consumed by current recipes.",
		"sources": [
			"Loot the crashed ship and supply crates",
		],
	},
	"Fuel Canister": {
		"description": "Pressurized canister of refined fuel. Salvage only — no mechanic uses it yet.",
		"sources": [
			"Loot the crashed ship and supply crates",
		],
	},
	"Emergency Flare": {
		"description": "Burns bright for one minute. Throwaway light source.",
		"sources": [
			"Fabricator: 1 Driftwood + 1 Fiber + 1 Glass Shard → 1 Flare (8s)",
		],
	},
	"Revival Injector": {
		"description": "Single-use stim that pulls a downed teammate back to consciousness at ~40% HP. The most important item in the bag.",
		"sources": [
			"Each survivor starts with 1",
			"Fabricator: 1 Stalker Fang + 1 Crawler Hide + 2 Algae → 1 Injector (25s)",
		],
	},
	"Comm Relay Module": {
		"description": "The brains of the rescue beacon. Slots into the Comm Relay Antenna structure, which channels for 90s to call evac.",
		"sources": [
			"Fabricator: 2 Electronics + 4 Metal Scrap + 2 Algae → 1 Module (30s)",
		],
	},
	# ── Equipment ───────────────────────────────────────────────────────────
	"Bone-Hewn Cleaver": {
		"description": "Heavy melee weapon (+5 damage, -0.2s cooldown). Engineer-only — Mira and Raya can't equip it.",
		"sources": [
			"Fabricator: 2 Stalker Fang + 3 Metal Scrap + 2 Crab Shell (25s)",
		],
	},
	"Salvaged Service Pistol": {
		"description": "Basic ranged sidearm (+2 damage, +1 tile range). Medic and Pilot only.",
		"sources": [
			"Fabricator: 4 Metal Scrap + 1 Electronics + 2 Driftwood (20s)",
		],
	},
	"Bioluminescent Coil Pistol": {
		"description": "Top-tier ranged weapon (+5 damage, +1 range, -0.3s cooldown). Medic and Pilot only.",
		"sources": [
			"Fabricator: 5 Metal Scrap + 3 Electronics + 4 Algae + 1 Stalker Fang (35s)",
		],
	},
	"Plated Combat Helmet": {
		"description": "Salvaged ship-hull helmet (+30 max HP). Any role can wear it.",
		"sources": [
			"Fabricator: 4 Metal Scrap + 1 Electronics + 1 Driftwood (22s)",
		],
	},
	"Crab Shell Vest": {
		"description": "Layered shell armor (+20 max HP). Cheapest body armor.",
		"sources": [
			"Fabricator: 6 Crab Shell + 3 Fiber (18s)",
		],
	},
	"Stalker Hide Cloak": {
		"description": "Lightweight cloak (+15 max HP, +20 move speed). Trades a bit of armor for mobility.",
		"sources": [
			"Fabricator: 3 Crawler Hide + 1 Stalker Fang + 2 Fiber + 1 Algae (25s)",
		],
	},
}


# Lookup with a sane fallback for items registered in ITEM_ICONS but not
# yet documented here. Returns a dict shaped like the entries above.
static func get_entry(item_name: String) -> Dictionary:
	if ENTRIES.has(item_name):
		return ENTRIES[item_name]
	return {
		"description": "(No glossary entry yet.)",
		"sources": ["Drops in the world."],
	}
