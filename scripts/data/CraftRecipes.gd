class_name CraftRecipes

# Recipe registry for the Fabricator. Each entry:
#   id        — stable string handle (used by the queue / save)
#   name      — display label
#   inputs    — { item_name: count } pulled from the shared team pool when
#               the player queues this recipe (failure aborts the queue).
#   output    — { item_name: count } delivered to the closest live unit on
#               completion, plus a loot toast above the fabricator.
#   time      — seconds spent crafting. Independent of who/where; the
#               fabricator just chews through its queue.
#   category  — UI grouping label.
#
# Recipes consume team-pool resources, so anyone carrying the input mats
# contributes — no need to physically haul them to the fabricator.
const RECIPES: Array = [
	{
		"id": "refine_metal",
		"name": "Refine Metal Scrap",
		"category": "Refining",
		"inputs":  {"Iron Chunk": 3},
		"output":  {"Metal Scrap": 1},
		"time":    8.0,
	},
	{
		"id": "make_electronics",
		"name": "Assemble Electronics",
		"category": "Refining",
		"inputs":  {"Copper Nugget": 2, "Sand Glass Shard": 1},
		"output":  {"Electronics": 1},
		"time":    12.0,
	},
	{
		"id": "make_bandages",
		"name": "Roll Bandages",
		"category": "Medical",
		"inputs":  {"Fiber": 2, "Bioluminescent Algae": 1},
		"output":  {"Bandages": 1},
		"time":    6.0,
	},
	{
		"id": "make_medsupplies",
		"name": "Pack Medical Supplies",
		"category": "Medical",
		"inputs":  {"Bioluminescent Algae": 1, "Crab Shell": 1, "Fiber": 2},
		"output":  {"Medical Supplies": 1},
		"time":    15.0,
	},
	{
		"id": "make_injector",
		"name": "Brew Revival Injector",
		"category": "Medical",
		"inputs":  {"Stalker Fang": 1, "Crawler Hide": 1, "Bioluminescent Algae": 2},
		"output":  {"Revival Injector": 1},
		"time":    25.0,
	},
	{
		"id": "make_rations",
		"name": "Cook Rations",
		"category": "Food",
		"inputs":  {"Crab Shell": 1, "Strange Egg": 1},
		"output":  {"Rations": 2},
		"time":    10.0,
	},
	{
		"id": "make_flare",
		"name": "Assemble Emergency Flare",
		"category": "Utility",
		"inputs":  {"Driftwood Piece": 1, "Fiber": 1, "Sand Glass Shard": 1},
		"output":  {"Emergency Flare": 1},
		"time":    8.0,
	},
	# The Comm Relay Module is the core of the run's endgame: feed it into
	# the Comm Relay Antenna (a placed structure) to call the rescue shuttle.
	# Expensive on purpose — gathering the inputs ramps Disturbance, so
	# crafting this commits the player to a hard final defense.
	{
		"id": "make_comm_relay_module",
		"name": "Build Comm Relay Module",
		"category": "Comms",
		"inputs":  {"Electronics": 2, "Metal Scrap": 4, "Bioluminescent Algae": 2},
		"output":  {"Comm Relay Module": 1},
		"time":    30.0,
	},
]


static func find(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}


static func get_categories() -> Array:
	var cats: Array = []
	for r in RECIPES:
		var c: String = r.category
		if not cats.has(c):
			cats.append(c)
	return cats


static func by_category(cat: String) -> Array:
	var out: Array = []
	for r in RECIPES:
		if r.category == cat:
			out.append(r)
	return out
