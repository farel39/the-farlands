extends Control

signal cut_requested(pos: Vector2)
signal inspect_requested

@onready var grid: Grid = get_tree().root.get_node("Main/Grid")
@onready var camera: Camera2D = get_tree().root.get_node("Main/Camera2D")

const BUILDINGS = {
	"DirtFloor": { "name": "Dirt Floor", "source_id": 0, "layer": 0, "navigable": true  },
}

# Heal items: item name → base HP restored. Applied to a unit's data.health.
# The Medic role applies MEDIC_HEAL_MULT on top of the base amount.
const HEAL_AMOUNTS: Dictionary = {
	"Bandages":         15.0,
	"Medical Supplies": 40.0,
}
const MEDIC_HEAL_MULT: float = 1.5

# Tooltip explaining what each stance does. Shown on hover for both the
# single-unit and group stance buttons. Click cycles Hold → Defend → Passive.
const STANCE_TOOLTIP: String = "Click to cycle stance:

• Hold — never engages, walks past enemies
• Defend — auto-engages anything seen (default)
• Passive — only retaliates when attacked

Right-click an enemy to attack it directly,
ignoring stance for that one target."

# Auto-heal tuning (medic only). Triggers when missing HP / item-heal ≥ EFFICIENCY,
# OR when target's HP fraction is below EMERGENCY_PCT (then any item is fair game).
const AUTO_HEAL_RANGE_TILES: float = 5.0
const AUTO_HEAL_COOLDOWN: float = 1.0
const AUTO_HEAL_EFFICIENCY: float = 0.8
const AUTO_HEAL_EMERGENCY_PCT: float = 0.2

const ITEM_ICONS: Dictionary = {
	"Metal Scrap":          "res://art/items/metal scrap realistic.png",
	"Electronics":          "res://art/items/electronics realistic.png",
	"Medical Supplies":     "res://art/items/medical supplies realistic.png",
	"Rations":              "res://art/items/rations realistic.png",
	"Bandages":             "res://art/items/bandages realistic.png",
	"Tools":                "res://art/items/wrench realistic.png",
	"Fuel Canister":        "res://art/items/fuel canister realistic.png",
	"Emergency Flare":      "res://art/items/emergency flare realistic.png",
	"Alien Shell":          "res://art/items/alien shell realistic.png",
	"Bioluminescent Algae": "res://art/items/bioluminescent algae realisitc.png",
	"Copper Nugget":        "res://art/items/copper nugget realistic.png",
	"Crab Shell":           "res://art/items/crab shell realistic.png",
	"Driftwood Piece":      "res://art/items/driftwood piece realistic.png",
	"Fiber":                "res://art/items/fiber realistic.png",
	"Iron Chunk":           "res://art/items/iron chunk realistic.png",
	"Sand Glass Shard":     "res://art/items/sand glass shard realistic.png",
	"Stone":                "res://art/items/stone realistic.png",
	"Strange Egg":          "res://art/items/strange egg realistic.png",
	"Revival Injector":     "res://art/items/revival injector realistic.png",
	"Crawler Hide":         "res://art/items/crawler hide realistic.png",
	"Stalker Fang":         "res://art/items/stalker fang realistic.png",
	"Mawling Wing":         "res://art/items/mawling wing realistic.png",
	"Comm Relay Module":    "res://art/items/comm relay module realistic.png",
}

const MONOLITH_LINES: Array = [
	"The symbols etched into the stone predate any known civilisation.",
	"You feel a faint vibration beneath your fingertips.",
	"Something about this structure interferes with your instruments.",
	"The stone is warm — far warmer than the surrounding air.",
	"Whoever built this was not human.",
	"The glyphs shift slightly when you're not looking directly at them.",
	"A low hum emanates from within. There is no visible source.",
]

var _tree_panel: PanelContainer
var _selected_tree: Vector2

var _unit_panel: PanelContainer
var _draft_btn: Button
var _follow_btn: Button
var _stance_btn: Button
var _selected_unit: Unit
var followed_unit: Unit = null

var _group_panel: PanelContainer
var _group_draft_btn: Button
var _group_stance_btn: Button
var _selected_group: Array = []

var _inv_panel: PanelContainer
var _inv_title: Label
var _inv_rows: GridContainer

var _dialog_panel: PanelContainer
var _dialog_portrait: TextureRect
var _dialog_name: Label
var _dialog_role: Label
var _dialog_text: Label
var _dialog_text_sep: HSeparator
var _dialog_draft_btn: Button
var _dialog_rng := RandomNumberGenerator.new()

var _sel_box_active: bool = false
var _sel_box: Rect2

var _construct_panel: PanelContainer
var _construct_vbox: VBoxContainer

var _global_inv_panel: PanelContainer
var _global_inv_vbox: VBoxContainer
var _global_inv_expanded: Dictionary = {}  # item_name → bool

var _units_panel: PanelContainer
var _units_vbox: VBoxContainer
var _all_units: Array = []

var _top_hud: BoxContainer  # VBoxContainer in current layout (left-edge column)
var _hud_bars: Dictionary = {}          # Unit → ProgressBar
var _last_drafted_ids: Array = []

var _bright_btn: Button
var _invincible_btn: Button
var _free_mats_btn: Button
var _test_event_btn: Button
var _test_event_panel: PanelContainer
# Debug dropdown — single toggle button at top-right; the four cheat
# buttons live inside the panel below it. Frees up the top-left for the
# game's main HUD (wave / disturbance / objective).
var _debug_toggle_btn: Button
var _debug_panel: PanelContainer
var _work_btn: Button

# Work-priorities panel state. Grid of unit-rows × task-columns; each cell
# cycles through HIGH/MED/LOW/OFF on click, color-coded for skim-readability.
var _work_panel: PanelContainer
var _work_grid: GridContainer
var _work_cells: Dictionary = {}  # (unit, task) → Button

# Orders / command-mode state. When `command_mode` is non-empty the cursor is
# in "give-orders" mode — left-click on the world dispatches the order to the
# clicked target, right-click exits the mode. `_command_indicator` is the
# top-of-screen banner showing the active mode.
var _orders_btn: Button
var _orders_panel: PanelContainer
var command_mode: String = ""
var _command_indicator: Label
# Read by Unit.take_damage to no-op incoming damage when true. Debug-only —
# toggled from the top-left button. Affects every Unit (not crabs).
var invincible_units: bool = false
var _minimap: Control
# Fullscreen-ish map overlay opened via the minimap's "Expand" button.
# Re-renders the same content as the minimap at a much larger size, with
# the same tooltips + click-to-recenter behavior.
var _map_panel: Control

# ── Character inventory panel ─────────────────────────────────────────────────
var _char_inv_panel: PanelContainer
var _char_inv_unit: Unit = null
var _char_inv_equip_slots: Dictionary = {}
var _char_inv_health_bar: ProgressBar
var _char_inv_portrait: TextureRect
var _char_inv_name_lbl: Label
var _char_inv_grid: GridContainer
var _char_inv_drop_slots: Array = []
var _auto_heal_btn: Button = null

# ── Heal flow panel ───────────────────────────────────────────────────────────
# State machine: 0=closed, 1=pick mode, 2=pick item (self), 3=pick target,
# 4=pick item (for chosen target). Steps 2 and 4 share the item-picker UI.
var _heal_panel: PanelContainer
var _heal_title_lbl: Label
var _heal_body: VBoxContainer
var _heal_state: int = 0
var _heal_actor: Unit = null
var _heal_target: Unit = null

# ── Wave banner / endgame overlay ─────────────────────────────────────────────
# Banner shows the current wave-state + countdown. Endgame overlay displays
# Victory or Defeat as a fullscreen modal at run end. Both are populated by
# WaveManager via signals (show_wave_banner / on_wave_state_changed).
var _wave_banner: PanelContainer
# Disturbance / threat bar — sits just below the wave banner. Fills as the
# player gathers, mines, and builds. Higher fill → harder waves. Drives
# the "every action affects the run" rubric: visible feedback so the
# player understands their actions matter.
var _threat_panel: PanelContainer
var _threat_bar: ProgressBar
var _threat_label: Label
const THREAT_BAR_MAX: float = 100.0
# Objective panel — lists the high-level steps the player should follow to
# call the rescue shuttle. The current step is highlighted; completed steps
# render dim with a check; future steps render dim without one. Updates
# from game state every frame.
var _quest_panel: PanelContainer
var _quest_lbl: RichTextLabel
var _wave_banner_main_lbl: Label
var _wave_banner_sub_lbl: Label
var _wave_banner_progress: ProgressBar
var _wave_msg_text: String = ""
var _wave_msg_timer: float = 0.0
var _wave_state: int = 0   # mirrors WaveManager.State
var _wave_index: int = 1
var _endgame_overlay: ColorRect
var _endgame_label: Label
var _endgame_stats_lbl: Label

# ── Loot panel ────────────────────────────────────────────────────────────────
var _loot_panel: PanelContainer
# Crafting (Fabricator) panel — recipe list + active queue. Built once,
# shown/hidden on demand. Anchor of the targeted fabricator is stored so
# refresh + queue actions know which one to read/write.
var _craft_panel: PanelContainer
var _craft_recipes_box: VBoxContainer
var _craft_queue_box: VBoxContainer
var _craft_progress_bar: ProgressBar
var _craft_anchor: Vector2 = Vector2(-1, -1)

# Generic choice-event modal: shown by EventManager when a branching event
# fires. The player picks one of the buttons; the chosen option's callback
# triggers immediate gameplay consequences (good + bad), and the choice is
# logged into run_stats.decisions for the end-of-run summary. Built once,
# reused for every choice event.
var _choice_panel: PanelContainer
var _choice_title_lbl: Label
var _choice_desc_lbl: Label
var _choice_btn_box: VBoxContainer
var _choice_pending_event: String = ""
const _CRAFT_RECIPES_GUI := preload("res://scripts/data/CraftRecipes.gd")
var _loot_title_lbl: Label
var _loot_grid: GridContainer
var _loot_source_inv: Dictionary = {}
var _loot_source_pos: Vector2 = Vector2(-1, -1)
var _loot_drop_slots: Array = []


func _ready() -> void:
	_tree_panel = _build_tree_panel()
	add_child(_tree_panel)

	_unit_panel = _build_unit_panel()
	add_child(_unit_panel)

	_group_panel = _build_group_panel()
	add_child(_group_panel)

	_inv_panel = _build_inventory_panel()
	add_child(_inv_panel)

	_char_inv_panel = _build_char_inv_panel()
	add_child(_char_inv_panel)
	_heal_panel = _build_heal_panel()
	add_child(_heal_panel)
	_loot_panel = _build_loot_panel()
	add_child(_loot_panel)

	_craft_panel = _build_craft_panel()
	add_child(_craft_panel)

	_choice_panel = _build_choice_panel()
	add_child(_choice_panel)

	_build_wave_banner()
	_build_endgame_overlay()

	_dialog_rng.randomize()
	_dialog_panel = _build_dialog_panel()
	add_child(_dialog_panel)

	_build_construct_ui()
	_build_top_hud()

	# All four debug buttons (Brightness / Invincible / Free Mats / Test
	# Event) are now stacked inside a single dropdown that hangs off a
	# small "Debug" toggle in the top-right corner. The top-left corner
	# is reserved for the game's main HUD (wave banner + disturbance bar
	# + quest objective).
	_build_debug_dropdown()
	_test_event_panel = _build_test_event_panel()
	add_child(_test_event_panel)

	_work_panel = _build_work_panel()
	add_child(_work_panel)

	_minimap = _MinimapControl.new(grid, camera, _all_units)
	const MM := 130
	_minimap.anchor_left   = 1.0
	_minimap.anchor_top    = 1.0
	_minimap.anchor_right  = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left   = -(MM + 4)
	_minimap.offset_right  = -4
	_minimap.offset_top    = -MM
	_minimap.offset_bottom = 0
	add_child(_minimap)

	# Minimize button — floats just above the top-right corner of the minimap
	var mm_min_btn := Button.new()
	mm_min_btn.text = "Minimize"
	mm_min_btn.custom_minimum_size = Vector2(44, 14)
	mm_min_btn.add_theme_font_size_override("font_size", 8)
	mm_min_btn.anchor_left   = 1.0
	mm_min_btn.anchor_top    = 1.0
	mm_min_btn.anchor_right  = 1.0
	mm_min_btn.anchor_bottom = 1.0
	mm_min_btn.offset_left   = -48
	mm_min_btn.offset_right  = -4
	mm_min_btn.offset_top    = -(MM + 14)
	mm_min_btn.offset_bottom = -(MM)
	add_child(mm_min_btn)

	# Restore button — hidden by default, bottom-right, same size as Inventory button
	var mm_restore_btn := Button.new()
	mm_restore_btn.text = "Minimap"
	mm_restore_btn.visible = false
	mm_restore_btn.anchor_left   = 1.0
	mm_restore_btn.anchor_top    = 1.0
	mm_restore_btn.anchor_right  = 1.0
	mm_restore_btn.anchor_bottom = 1.0
	mm_restore_btn.offset_left   = -124
	mm_restore_btn.offset_right  = -4
	mm_restore_btn.offset_top    = -40
	mm_restore_btn.offset_bottom = 0
	add_child(mm_restore_btn)

	mm_min_btn.pressed.connect(func():
		_minimap.visible = false
		mm_min_btn.visible = false
		mm_restore_btn.visible = true
	)
	mm_restore_btn.pressed.connect(func():
		_minimap.visible = true
		mm_min_btn.visible = true
		mm_restore_btn.visible = false
	)

	# Expand button — opens a fullscreen-ish version of the minimap with
	# tooltips on every marker and click-to-recenter. Sits to the left of
	# the Minimize button.
	var mm_expand_btn := Button.new()
	mm_expand_btn.text = "Expand"
	mm_expand_btn.custom_minimum_size = Vector2(48, 14)
	mm_expand_btn.add_theme_font_size_override("font_size", 8)
	mm_expand_btn.anchor_left   = 1.0
	mm_expand_btn.anchor_top    = 1.0
	mm_expand_btn.anchor_right  = 1.0
	mm_expand_btn.anchor_bottom = 1.0
	mm_expand_btn.offset_left   = -100
	mm_expand_btn.offset_right  = -52
	mm_expand_btn.offset_top    = -(MM + 14)
	mm_expand_btn.offset_bottom = -(MM)
	add_child(mm_expand_btn)
	mm_expand_btn.pressed.connect(_on_map_expand_pressed)

	_map_panel = _MapPanelControl.new(grid, camera, _all_units)
	_map_panel.visible = false
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_panel.z_index = 70
	add_child(_map_panel)


# Small popup that lists every available order. Picking one closes the panel
# and enters the corresponding command mode (cursor stays in mode until the
# player right-clicks).
func _build_orders_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left   = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 496
	panel.offset_right  = 696
	panel.offset_bottom = -44
	panel.offset_top    = -240
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Orders"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.pressed.connect(func(): _orders_panel.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# Available orders. Add new ones here as new task types come online.
	var orders: Array = [
		["repair",   "Repair",   "Repair damaged walls. Engineer-priority."],
		["harvest",  "Harvest",  "Chop trees for driftwood, fiber, and algae."],
		["mine",     "Mine",     "Mine rocks for stone, iron, copper, glass."],
		["build",    "Build",    "Resume a stalled blueprint once materials are available."],
		["revive",   "Revive",   "Send the next free unit to revive a downed teammate."],
		["demolish", "Demolish", "Tear down a wall (or cancel a blueprint with refund)."],
		["cancel",   "Cancel",   "Click any queued task target to cancel it (harvest, mine, repair, etc.)."],
	]
	for entry in orders:
		var key: String = entry[0]
		var label: String = entry[1]
		var hint: String = entry[2]
		var btn := Button.new()
		btn.text = label
		btn.tooltip_text = hint
		btn.pressed.connect(func(): enter_command_mode(key))
		vbox.add_child(btn)

	panel.add_child(vbox)
	return panel


func _on_orders_btn_pressed() -> void:
	if _orders_panel == null:
		return
	if _orders_panel.visible:
		_orders_panel.visible = false
		return
	_close_bottom_panels()
	_orders_panel.visible = true


# Public so Main can also exit on input events (right-click) without poking
# internal state. Sets the mode label, sets the cursor to a custom shape so
# the player can tell they're in mode.
func enter_command_mode(mode: String) -> void:
	command_mode = mode
	if _orders_panel != null:
		_orders_panel.visible = false
	if _command_indicator != null:
		_command_indicator.text = "%s mode  —  left-click targets   |   right-click to exit" % mode.capitalize()
		_command_indicator.visible = true
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func exit_command_mode() -> void:
	command_mode = ""
	if _command_indicator != null:
		_command_indicator.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _build_work_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	# Bottom-anchored, grows upward from above the Work button — matches the
	# Construct / Inventory / Units panels for consistent UX.
	panel.anchor_left   = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 372
	panel.offset_right  = 920
	panel.offset_bottom = -44
	panel.offset_top    = -360
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var vbox := VBoxContainer.new()

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Work Priorities"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.pressed.connect(func(): _work_panel.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Click a cell to cycle: HIGH → MED → LOW → OFF"
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(hint)

	_work_grid = GridContainer.new()
	_work_grid.columns = 1 + UnitData.TASK_TYPES.size()  # unit name + 6 task cols
	_work_grid.add_theme_constant_override("h_separation", 6)
	_work_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_work_grid)

	panel.add_child(vbox)
	return panel


# Toggle the panel; rebuild contents on open so newly-spawned / dead units
# show up correctly without needing a per-frame refresh.
func _on_work_btn_pressed() -> void:
	if _work_panel == null:
		return
	if _work_panel.visible:
		_work_panel.visible = false
		return
	_close_bottom_panels()
	_refresh_work_panel()
	_work_panel.visible = true


# Wipes and re-populates the grid from current `_all_units` + their priority dicts.
func _refresh_work_panel() -> void:
	if _work_grid == null:
		return
	for child in _work_grid.get_children():
		child.queue_free()
	_work_cells.clear()

	# Header row: empty cell for unit-name column + short task labels.
	var col_lbl := Label.new()
	col_lbl.text = "Unit"
	col_lbl.add_theme_font_size_override("font_size", 11)
	_work_grid.add_child(col_lbl)
	const TASK_HEADERS: Dictionary = {
		"combat":  "Combat",
		"heal":    "Heal",
		"repair":  "Repair",
		"build":   "Build",
		"harvest": "Harvest",
		"mine":    "Mine",
		"gather":  "Gather",
	}
	for task_type in UnitData.TASK_TYPES:
		var lbl := Label.new()
		lbl.text = TASK_HEADERS.get(task_type, task_type)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_work_grid.add_child(lbl)

	# One row per live unit.
	for u in _all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if unit_node.is_dead():
			continue
		# Unit-name cell: portrait + name + role, matching the Units panel.
		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 6)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(28, 28)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if unit_node.data.portrait:
			portrait.texture = unit_node.data.portrait
		name_box.add_child(portrait)
		var name_col := VBoxContainer.new()
		name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_lbl := Label.new()
		name_lbl.text = unit_node.data.name
		name_col.add_child(name_lbl)
		var role_lbl := Label.new()
		role_lbl.text = unit_node.data.role
		role_lbl.modulate = Color(0.7, 0.7, 0.7)
		role_lbl.add_theme_font_size_override("font_size", 10)
		name_col.add_child(role_lbl)
		name_box.add_child(name_col)
		_work_grid.add_child(name_box)
		for task_type in UnitData.TASK_TYPES:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(48, 24)
			var unit_ref: Unit = unit_node
			var task_ref: String = task_type
			btn.pressed.connect(func(): _cycle_work_priority(unit_ref, task_ref))
			_work_cells[[unit_node, task_type]] = btn
			_work_grid.add_child(btn)
			_update_work_button(btn, unit_node, task_type)


# Cycle: OFF → LOW → MED → HIGH → OFF. Updates the cell's text/color.
func _cycle_work_priority(unit: Unit, task_type: String) -> void:
	if not is_instance_valid(unit):
		return
	var current: int = int(unit.data.work_priorities.get(task_type, UnitData.Priority.MED))
	var next_pri: int = (current + 1) % 4
	unit.data.work_priorities[task_type] = next_pri
	var btn: Button = _work_cells.get([unit, task_type], null)
	if btn != null:
		_update_work_button(btn, unit, task_type)


func _update_work_button(btn: Button, unit: Unit, task_type: String) -> void:
	var pri: int = int(unit.data.work_priorities.get(task_type, UnitData.Priority.MED))
	var label_text: String
	var col: Color
	match pri:
		UnitData.Priority.HIGH:
			label_text = "HIGH"
			col = Color(0.30, 0.85, 0.35)
		UnitData.Priority.MED:
			label_text = "MED"
			col = Color(0.95, 0.85, 0.30)
		UnitData.Priority.LOW:
			label_text = "LOW"
			col = Color(0.95, 0.55, 0.30)
		_:
			label_text = "OFF"
			col = Color(0.45, 0.45, 0.45)
	btn.text = label_text
	btn.modulate = col


func _on_bright_btn_pressed() -> void:
	var main := get_tree().root.get_node("Main")
	main.toggle_brightness()
	if main._bright_mode:
		_bright_btn.text = "Brightness: ON"
	else:
		_bright_btn.text = "Brightness: OFF"


func _on_invincible_btn_pressed() -> void:
	invincible_units = not invincible_units
	_invincible_btn.text = "Invincible: ON" if invincible_units else "Invincible: OFF"
	# Tint the button so it's obvious at a glance.
	_invincible_btn.modulate = Color(0.55, 1.0, 0.65) if invincible_units else Color(1, 1, 1)


# Debug: dump 999 of every item known to ITEM_ICONS into the first live unit.
# Shared inventory rules mean any other unit can spend the stockpile too —
# blueprints, repairs, healing, everything. Fires notify_inventory_changed
# so deferred build tasks dispatch the moment the cheat lands.
# Debug: build the popup panel that lists every random event with a button.
# Hidden by default; shown by the Test Event toggle. Each button calls
# EventManager.fire_event_by_id which bypasses the scheduler + wave gate.
func _build_test_event_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	# Anchored to the top-right corner, sits to the LEFT of the debug
	# dropdown so it doesn't fall off-screen when opened from the new
	# debug-panel location.
	panel.anchor_left   = 1.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = -388
	panel.offset_right  = -168
	panel.offset_top    = 40
	panel.custom_minimum_size = Vector2(220, 0)
	panel.z_index = 50

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Debug — Fire Event"
	title.add_theme_font_size_override("font_size", 12)
	title.modulate = Color(0.92, 0.92, 0.95)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# One button per registered event. Reads the live EVENTS array off the
	# manager so adding/removing events automatically updates the panel.
	var events: Array = [
		{"id": "crab_raid",        "label": "Crab Raid"},
		{"id": "lightning_storm",  "label": "Lightning Storm"},
		{"id": "supply_drop",      "label": "Supply Drop"},
		{"id": "brood_mother",     "label": "Brood Mother"},
		{"id": "mysterious_beacon","label": "Mysterious Beacon"},
		{"id": "tempting_eggs",    "label": "Glowing Egg Cluster"},
	]
	for entry: Dictionary in events:
		var btn := Button.new()
		btn.text = String(entry.label)
		btn.custom_minimum_size = Vector2(0, 28)
		var event_id: String = String(entry.id)
		btn.pressed.connect(func(): _fire_test_event(event_id))
		vbox.add_child(btn)
	return panel


func _on_test_event_btn_pressed() -> void:
	if _test_event_panel == null:
		return
	_test_event_panel.visible = not _test_event_panel.visible


# Forward-trigger an event via EventManager.fire_event_by_id. Closes the
# debug panel so it doesn't sit over the world during the event's effects.
func _fire_test_event(event_id: String) -> void:
	if _test_event_panel != null:
		_test_event_panel.visible = false
	var main_node: Node = grid.get_parent() if grid != null else null
	if main_node == null:
		return
	var em: Node = main_node.get_node_or_null("EventManager")
	if em != null and em.has_method("fire_event_by_id"):
		em.fire_event_by_id(event_id)


# Build the cheat dropdown: a small "Debug" toggle button anchored to the
# top-right corner, and a panel below it that contains every cheat button.
# Toggle visibility by clicking the button; the panel is hidden by default.
# Keeps the top-left clear for the game's main HUD.
func _build_debug_dropdown() -> void:
	_debug_toggle_btn = Button.new()
	_debug_toggle_btn.text = "Debug ▾"
	_debug_toggle_btn.tooltip_text = "Toggle debug / cheat dropdown."
	_debug_toggle_btn.anchor_left   = 1.0
	_debug_toggle_btn.anchor_top    = 0.0
	_debug_toggle_btn.anchor_right  = 1.0
	_debug_toggle_btn.anchor_bottom = 0.0
	_debug_toggle_btn.offset_left   = -100
	_debug_toggle_btn.offset_right  = -8
	_debug_toggle_btn.offset_top    = 8
	_debug_toggle_btn.offset_bottom = 36
	_debug_toggle_btn.pressed.connect(_on_debug_toggle_pressed)
	add_child(_debug_toggle_btn)

	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.anchor_left   = 1.0
	_debug_panel.anchor_top    = 0.0
	_debug_panel.anchor_right  = 1.0
	_debug_panel.anchor_bottom = 0.0
	_debug_panel.offset_left   = -160
	_debug_panel.offset_right  = -8
	_debug_panel.offset_top    = 40
	_debug_panel.z_index = 50

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var hdr := Label.new()
	hdr.text = "Debug"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.modulate = Color(0.85, 0.85, 0.95)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hdr)
	col.add_child(HSeparator.new())

	# Brightness toggle.
	_bright_btn = Button.new()
	_bright_btn.text = "Brightness: OFF"
	_bright_btn.custom_minimum_size = Vector2(0, 28)
	_bright_btn.pressed.connect(_on_bright_btn_pressed)
	col.add_child(_bright_btn)

	# Unit invincibility.
	_invincible_btn = Button.new()
	_invincible_btn.text = "Invincible: OFF"
	_invincible_btn.tooltip_text = "Debug — when ON, units take no damage."
	_invincible_btn.custom_minimum_size = Vector2(0, 28)
	_invincible_btn.pressed.connect(_on_invincible_btn_pressed)
	col.add_child(_invincible_btn)

	# Free materials.
	_free_mats_btn = Button.new()
	_free_mats_btn.text = "Free Mats"
	_free_mats_btn.tooltip_text = "Debug — dump 999 of every resource into the team."
	_free_mats_btn.custom_minimum_size = Vector2(0, 28)
	_free_mats_btn.pressed.connect(_on_free_mats_btn_pressed)
	col.add_child(_free_mats_btn)

	# Manual event trigger.
	_test_event_btn = Button.new()
	_test_event_btn.text = "Test Event"
	_test_event_btn.tooltip_text = "Debug — manually fire any random event."
	_test_event_btn.custom_minimum_size = Vector2(0, 28)
	_test_event_btn.pressed.connect(_on_test_event_btn_pressed)
	col.add_child(_test_event_btn)

	_debug_panel.add_child(col)
	add_child(_debug_panel)


func _on_debug_toggle_pressed() -> void:
	if _debug_panel == null:
		return
	_debug_panel.visible = not _debug_panel.visible
	_debug_toggle_btn.text = "Debug ▴" if _debug_panel.visible else "Debug ▾"


func _on_free_mats_btn_pressed() -> void:
	const STOCKPILE_QTY: int = 999
	var recipient: Unit = null
	for u in _all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if unit_node.is_dead() or unit_node.is_downed or unit_node.evacuated:
			continue
		recipient = unit_node
		break
	if recipient == null:
		return
	for item_name: String in ITEM_ICONS.keys():
		recipient.data.inventory[item_name] = int(recipient.data.inventory.get(item_name, 0)) + STOCKPILE_QTY
	# Brief flash so the player sees the click registered.
	_free_mats_btn.modulate = Color(1.0, 1.0, 0.5)
	var tween := create_tween()
	tween.tween_property(_free_mats_btn, "modulate", Color(1, 1, 1), 0.4)
	# Wake any deferred builds waiting on materials.
	var main_node: Node = grid.get_parent()
	if main_node != null and main_node.has_method("notify_inventory_changed"):
		main_node.notify_inventory_changed()


# ── Panel builders ────────────────────────────────────────────────────────────

func _build_tree_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Tree"
	var cut_btn := Button.new()
	cut_btn.text = "Cut"
	cut_btn.pressed.connect(_on_cut_pressed)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): panel.visible = false)
	vbox.add_child(title)
	vbox.add_child(cut_btn)
	vbox.add_child(cancel)
	panel.add_child(vbox)
	return panel


func _build_unit_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var uname := Label.new()
	uname.text = "Colonist"
	_draft_btn = Button.new()
	_draft_btn.pressed.connect(_on_draft_pressed)
	_follow_btn = Button.new()
	_follow_btn.pressed.connect(_on_follow_pressed)
	_stance_btn = Button.new()
	_stance_btn.tooltip_text = STANCE_TOOLTIP
	_stance_btn.pressed.connect(_on_stance_pressed)
	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	inv_btn.pressed.connect(_on_unit_inv_btn_pressed)
	var heal_shortcut := Button.new()
	heal_shortcut.text = "Heal"
	heal_shortcut.pressed.connect(_on_unit_panel_heal_pressed)
	vbox.add_child(uname)
	vbox.add_child(_draft_btn)
	vbox.add_child(_follow_btn)
	vbox.add_child(_stance_btn)
	vbox.add_child(inv_btn)
	vbox.add_child(heal_shortcut)
	panel.add_child(vbox)
	return panel


func _build_group_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Group"
	_group_draft_btn = Button.new()
	_group_draft_btn.pressed.connect(_on_group_draft_pressed)
	_group_stance_btn = Button.new()
	_group_stance_btn.tooltip_text = STANCE_TOOLTIP
	_group_stance_btn.pressed.connect(_on_group_stance_pressed)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): panel.visible = false)
	vbox.add_child(title)
	vbox.add_child(_group_draft_btn)
	vbox.add_child(_group_stance_btn)
	vbox.add_child(cancel)
	panel.add_child(vbox)
	return panel


func _build_inventory_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var vbox := VBoxContainer.new()
	_inv_title = Label.new()
	_inv_title.text = "Inventory"
	vbox.add_child(_inv_title)
	_inv_rows = GridContainer.new()
	_inv_rows.columns = 5
	vbox.add_child(_inv_rows)
	vbox.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): panel.visible = false)
	vbox.add_child(close)
	panel.add_child(vbox)
	return panel


func _build_dialog_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = Vector2(320, 0)
	var vbox := VBoxContainer.new()

	var top := HBoxContainer.new()
	_dialog_portrait = TextureRect.new()
	_dialog_portrait.custom_minimum_size = Vector2(64, 64)
	_dialog_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialog_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialog_portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(_dialog_portrait)
	var name_col := VBoxContainer.new()
	_dialog_name = Label.new()
	_dialog_role = Label.new()
	_dialog_role.modulate = Color(0.7, 0.7, 0.7)
	name_col.add_child(_dialog_name)
	name_col.add_child(_dialog_role)
	top.add_child(name_col)
	vbox.add_child(top)
	vbox.add_child(HSeparator.new())

	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_dialog_text)
	_dialog_text_sep = HSeparator.new()
	vbox.add_child(_dialog_text_sep)

	var btns := HBoxContainer.new()
	_dialog_draft_btn = Button.new()
	_dialog_draft_btn.pressed.connect(_on_dialog_draft_pressed)
	btns.add_child(_dialog_draft_btn)
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	inspect_btn.pressed.connect(_on_inspect_pressed)
	btns.add_child(inspect_btn)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): panel.visible = false)
	btns.add_child(close)
	vbox.add_child(btns)

	panel.add_child(vbox)
	return panel


# ── Construction UI ───────────────────────────────────────────────────────────

func _build_construct_ui() -> void:
	# Panel: anchored to bottom-left, grows upward, fixed width
	_construct_panel = PanelContainer.new()
	_construct_panel.visible = false
	_construct_panel.anchor_left   = 0.0
	_construct_panel.anchor_top    = 1.0
	_construct_panel.anchor_right  = 0.0
	_construct_panel.anchor_bottom = 1.0
	_construct_panel.offset_left   = 0
	_construct_panel.offset_right  = 260
	_construct_panel.offset_bottom = -44
	_construct_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_construct_vbox = VBoxContainer.new()
	_construct_panel.add_child(_construct_vbox)
	add_child(_construct_panel)

	# "Construct" button — bottom-left, above nothing
	var btn := Button.new()
	btn.text = "Construct"
	btn.anchor_left   = 0.0
	btn.anchor_top    = 1.0
	btn.anchor_right  = 0.0
	btn.anchor_bottom = 1.0
	btn.offset_left   = 0
	btn.offset_right  = 120
	btn.offset_top    = -40
	btn.offset_bottom = 0
	btn.pressed.connect(_on_construct_btn_pressed)
	add_child(btn)

	# Global inventory panel — grows upward from above the inventory button
	_global_inv_panel = PanelContainer.new()
	_global_inv_panel.visible = false
	_global_inv_panel.anchor_left   = 0.0
	_global_inv_panel.anchor_top    = 1.0
	_global_inv_panel.anchor_right  = 0.0
	_global_inv_panel.anchor_bottom = 1.0
	_global_inv_panel.offset_left   = 124
	_global_inv_panel.offset_right  = 400
	_global_inv_panel.offset_bottom = -44
	_global_inv_panel.offset_top    = -500
	_global_inv_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_global_inv_vbox = VBoxContainer.new()
	_global_inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_inv_vbox.add_theme_constant_override("separation", 32)
	scroll.add_child(_global_inv_vbox)
	_global_inv_panel.add_child(scroll)
	add_child(_global_inv_panel)

	# "Inventory" button — sits right of Construct
	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	inv_btn.anchor_left   = 0.0
	inv_btn.anchor_top    = 1.0
	inv_btn.anchor_right  = 0.0
	inv_btn.anchor_bottom = 1.0
	inv_btn.offset_left   = 124
	inv_btn.offset_right  = 244
	inv_btn.offset_top    = -40
	inv_btn.offset_bottom = 0
	inv_btn.pressed.connect(_on_global_inv_btn_pressed)
	add_child(inv_btn)

	# Units panel — grows upward, scrollable
	_units_panel = PanelContainer.new()
	_units_panel.visible = false
	_units_panel.anchor_left   = 0.0
	_units_panel.anchor_top    = 1.0
	_units_panel.anchor_right  = 0.0
	_units_panel.anchor_bottom = 1.0
	_units_panel.offset_left   = 248
	_units_panel.offset_right  = 850
	_units_panel.offset_bottom = -44
	_units_panel.offset_top    = -500
	_units_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var units_scroll := ScrollContainer.new()
	units_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	units_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_units_vbox = VBoxContainer.new()
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units_scroll.add_child(_units_vbox)
	_units_panel.add_child(units_scroll)
	add_child(_units_panel)

	# "Units" button
	var units_btn := Button.new()
	units_btn.text = "Units"
	units_btn.anchor_left   = 0.0
	units_btn.anchor_top    = 1.0
	units_btn.anchor_right  = 0.0
	units_btn.anchor_bottom = 1.0
	units_btn.offset_left   = 248
	units_btn.offset_right  = 368
	units_btn.offset_top    = -40
	units_btn.offset_bottom = 0
	units_btn.pressed.connect(_on_units_btn_pressed)
	add_child(units_btn)

	# "Work" button — opens the priorities panel.
	_work_btn = Button.new()
	_work_btn.text = "Work"
	_work_btn.tooltip_text = "Per-unit work priorities (HIGH/MED/LOW/OFF)"
	_work_btn.anchor_left   = 0.0
	_work_btn.anchor_top    = 1.0
	_work_btn.anchor_right  = 0.0
	_work_btn.anchor_bottom = 1.0
	_work_btn.offset_left   = 372
	_work_btn.offset_right  = 492
	_work_btn.offset_top    = -40
	_work_btn.offset_bottom = 0
	_work_btn.pressed.connect(_on_work_btn_pressed)
	add_child(_work_btn)

	# "Orders" button + popup panel — bulk-order mode (Repair / Harvest /
	# Demolish). Click an order, then left-click many targets in the world,
	# right-click to exit the mode.
	_orders_panel = _build_orders_panel()
	add_child(_orders_panel)
	_orders_btn = Button.new()
	_orders_btn.text = "Orders"
	_orders_btn.tooltip_text = "Pick an order, then left-click targets. Right-click to exit."
	_orders_btn.anchor_left   = 0.0
	_orders_btn.anchor_top    = 1.0
	_orders_btn.anchor_right  = 0.0
	_orders_btn.anchor_bottom = 1.0
	_orders_btn.offset_left   = 496
	_orders_btn.offset_right  = 616
	_orders_btn.offset_top    = -40
	_orders_btn.offset_bottom = 0
	_orders_btn.pressed.connect(_on_orders_btn_pressed)
	add_child(_orders_btn)

	# Command-mode banner — pinned to the top, hidden until a mode is active.
	_command_indicator = Label.new()
	_command_indicator.visible = false
	_command_indicator.anchor_left   = 0.5
	_command_indicator.anchor_right  = 0.5
	_command_indicator.anchor_top    = 0.0
	_command_indicator.anchor_bottom = 0.0
	_command_indicator.offset_left   = -260
	_command_indicator.offset_right  = 260
	_command_indicator.offset_top    = 44
	_command_indicator.offset_bottom = 70
	_command_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_command_indicator.modulate = Color(1.0, 0.85, 0.30)
	_command_indicator.add_theme_font_size_override("font_size", 14)
	_command_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_indicator.z_index = 70
	add_child(_command_indicator)


func _close_bottom_panels() -> void:
	_construct_panel.visible = false
	_global_inv_panel.visible = false
	_units_panel.visible = false
	if _work_panel != null:
		_work_panel.visible = false
	if _orders_panel != null:
		_orders_panel.visible = false


func _on_construct_btn_pressed() -> void:
	if _construct_panel.visible:
		_construct_panel.visible = false
	else:
		_close_bottom_panels()
		_show_categories()


func _show_categories() -> void:
	for c in _construct_vbox.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Build"
	title.name = "CategoryRow"
	_construct_vbox.add_child(title)
	for cat in BuildingDefs.get_categories():
		var btn := Button.new()
		btn.text = cat
		btn.pressed.connect(_show_items.bind(cat))
		_construct_vbox.add_child(btn)
	_construct_panel.visible = true


func _show_items(category: String) -> void:
	for c in _construct_vbox.get_children():
		c.queue_free()
	var back := Button.new()
	back.text = "← Back"
	back.pressed.connect(_show_categories)
	_construct_vbox.add_child(back)
	var title := Label.new()
	title.text = category
	_construct_vbox.add_child(title)
	for bname in BuildingDefs.get_by_category(category):
		var def: Dictionary = BuildingDefs.DEFS[bname]
		var row := HBoxContainer.new()
		# Icon
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var tex := load(def.sprite) as Texture2D
		if tex:
			icon.texture = tex
		row.add_child(icon)
		# Name + cost label
		var info_col := VBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = bname
		info_col.add_child(name_lbl)
		var cost_parts: Array = []
		for item in def.cost:
			cost_parts.append("%s ×%d" % [item, def.cost[item]])
		var cost_lbl := Label.new()
		cost_lbl.text = ", ".join(cost_parts)
		cost_lbl.modulate = Color(0.75, 0.75, 0.75)
		info_col.add_child(cost_lbl)
		row.add_child(info_col)
		# Place button
		var place_btn := Button.new()
		place_btn.text = "Place"
		place_btn.pressed.connect(_on_place_pressed.bind(def))
		row.add_child(place_btn)
		_construct_vbox.add_child(row)


func _on_place_pressed(def: Dictionary) -> void:
	# Keep the Construct panel open so the player can place several walls in a
	# row, or switch to a different building type, without re-opening the tab.
	# ESC (handled in Grid) exits blueprint mode when they're done.
	grid.enter_blueprint_mode(def)


# ── Global inventory ──────────────────────────────────────────────────────────

func _on_global_inv_btn_pressed() -> void:
	if _global_inv_panel.visible:
		_global_inv_panel.visible = false
		return
	_close_bottom_panels()
	_refresh_global_inventory()
	_global_inv_panel.visible = true


func _refresh_global_inventory() -> void:
	for c in _global_inv_vbox.get_children():
		c.queue_free()

	# Collect sources: characters only
	var sources: Array = []
	for u in _all_units:
		var u_node := u as Unit
		if not u_node.data.inventory.is_empty():
			sources.append({"label": u_node.data.name, "inv": u_node.data.inventory})

	# Aggregate totals per item
	var totals: Dictionary = {}
	for src in sources:
		for item in src.inv:
			totals[item] = totals.get(item, 0) + src.inv[item]

	if totals.is_empty():
		var lbl := Label.new()
		lbl.text = "No resources found."
		_global_inv_vbox.add_child(lbl)
		return

	var title := Label.new()
	title.text = "All Resources"
	_global_inv_vbox.add_child(title)
	_global_inv_vbox.add_child(HSeparator.new())

	for item in totals:
		var expanded: bool = _global_inv_expanded.get(item, false)

		# Clickable header row: icon + name + total + arrow
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 40)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ITEM_ICONS.has(item):
			var tex := load(ITEM_ICONS[item]) as Texture2D
			if tex:
				icon.texture = tex
		row.add_child(icon)
		var name_lbl := Label.new()
		name_lbl.text = item
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)
		var qty_lbl := Label.new()
		qty_lbl.text = "×%d" % totals[item]
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(qty_lbl)
		var arrow_lbl := Label.new()
		arrow_lbl.text = "▲" if expanded else "▼"
		arrow_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(arrow_lbl)
		btn.add_child(row)

		var item_key: String = item  # capture for lambda
		btn.pressed.connect(func():
			_global_inv_expanded[item_key] = not _global_inv_expanded.get(item_key, false)
			_refresh_global_inventory.call_deferred()
		)
		_global_inv_vbox.add_child(btn)

		# Sub-rows: where each chunk is, only shown when expanded
		if expanded:
			for src in sources:
				if src.inv.has(item):
					var loc_lbl := Label.new()
					loc_lbl.text = "  %s: ×%d" % [src.label, src.inv[item]]
					loc_lbl.modulate = Color(0.7, 0.7, 0.7)
					_global_inv_vbox.add_child(loc_lbl)


# ── Units panel ──────────────────────────────────────────────────────────────

func register_units(units: Array) -> void:
	_all_units = units


func _on_units_btn_pressed() -> void:
	if _units_panel.visible:
		_units_panel.visible = false
		return
	_close_bottom_panels()
	_refresh_units_panel()
	_units_panel.visible = true


func _refresh_units_panel() -> void:
	for c in _units_vbox.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "Units"
	_units_vbox.add_child(title)
	_units_vbox.add_child(HSeparator.new())

	for u in _all_units:
		var u_node := u as Unit

		# Card: clicking anywhere on card centers camera and escapes follow mode
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				followed_unit = null
				camera.center_on(u_node.position)
		)

		# Wrap card contents in a VBoxContainer so button sits below the row
		var card_vbox := VBoxContainer.new()
		card_vbox.mouse_filter = Control.MOUSE_FILTER_PASS

		# Single row: [portrait | name/role/health | inventory grid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_PASS

		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(48, 48)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_PASS
		if u_node.data.portrait:
			portrait.texture = u_node.data.portrait
		row.add_child(portrait)

		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(100, 0)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_PASS

		var name_lbl := Label.new()
		name_lbl.text = u_node.data.name
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = u_node.data.role
		role_lbl.modulate = Color(0.7, 0.7, 0.7)
		role_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(role_lbl)

		var bar := _make_health_bar(0, 12)
		bar.max_value = u_node.data.max_health
		bar.value = u_node.data.health
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(bar)

		row.add_child(col)

		# 2×10 inventory grid to the right
		var inv_grid := GridContainer.new()
		inv_grid.columns = 10
		inv_grid.add_theme_constant_override("h_separation", 2)
		inv_grid.add_theme_constant_override("v_separation", 2)
		inv_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inv_grid.mouse_filter = Control.MOUSE_FILTER_PASS
		var items_list := u_node.data.inventory.keys()
		for i in 20:
			var slot := _UnitInvSlot.new(self, u_node)
			if i < items_list.size():
				slot.set_item(items_list[i], u_node.data.inventory[items_list[i]])
			inv_grid.add_child(slot)
		row.add_child(inv_grid)
		card_vbox.add_child(row)

		# "View Profile" button — opens char inv and closes units panel
		var profile_btn := Button.new()
		profile_btn.text = "View Profile"
		profile_btn.flat = false
		profile_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		profile_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		profile_btn.pressed.connect(func():
			_units_panel.visible = false
			show_char_inv_panel(u_node)
		)
		card_vbox.add_child(profile_btn)

		card.add_child(card_vbox)
		_units_vbox.add_child(card)
		_units_vbox.add_child(HSeparator.new())


# ── Selection box ─────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _sel_box_active:
		return
	draw_rect(_sel_box, Color(0.2, 0.8, 0.2, 0.15), true)
	draw_rect(_sel_box, Color(0.2, 0.8, 0.2, 1.0), false, 1.0)


func update_selection_box(start: Vector2, end: Vector2) -> void:
	_sel_box = Rect2(start, end - start).abs()
	_sel_box_active = true
	queue_redraw()


func hide_selection_box() -> void:
	_sel_box_active = false
	queue_redraw()


# ── Tree panel ────────────────────────────────────────────────────────────────

func show_tree_panel(pos: Vector2, screen_pos: Vector2) -> void:
	_selected_tree = pos
	_tree_panel.position = screen_pos + Vector2(8, 8)
	_tree_panel.visible = true

func _on_cut_pressed() -> void:
	_tree_panel.visible = false
	cut_requested.emit(_selected_tree)


# ── Unit panel ────────────────────────────────────────────────────────────────

func show_unit_panel(unit: Unit, screen_pos: Vector2) -> void:
	_selected_unit = unit
	_draft_btn.text = "Undraft" if unit.drafted else "Draft"
	_follow_btn.text = "Unfollow" if followed_unit == unit else "Follow Camera"
	_stance_btn.text = "Stance: %s" % unit.stance_name()
	_unit_panel.position = screen_pos + Vector2(8, 8)
	_unit_panel.visible = true


func _on_stance_pressed() -> void:
	if _selected_unit == null or not is_instance_valid(_selected_unit):
		return
	_selected_unit.cycle_stance()
	_stance_btn.text = "Stance: %s" % _selected_unit.stance_name()

func hide_unit_panel() -> void:
	_unit_panel.visible = false


func _on_draft_pressed() -> void:
	_selected_unit.set_drafted(not _selected_unit.drafted)
	_draft_btn.text = "Undraft" if _selected_unit.drafted else "Draft"


func _on_follow_pressed() -> void:
	if followed_unit == _selected_unit:
		followed_unit = null
	else:
		followed_unit = _selected_unit
	_follow_btn.text = "Unfollow" if followed_unit == _selected_unit else "Follow Camera"


# ── Group panel ───────────────────────────────────────────────────────────────

func show_group_panel(units: Array, screen_pos: Vector2) -> void:
	_selected_group = units
	var all_drafted: bool = units.all(func(u): return u.drafted)
	_group_draft_btn.text = "Undraft All" if all_drafted else "Draft All"
	_group_stance_btn.text = "Stance: %s" % _group_stance_label(units)
	_group_panel.position = screen_pos + Vector2(8, 8)
	_group_panel.visible = true

func _on_group_draft_pressed() -> void:
	var all_drafted: bool = _selected_group.all(func(u): return u.drafted)
	for u in _selected_group:
		u.set_drafted(not all_drafted)
	_group_draft_btn.text = "Draft All" if all_drafted else "Undraft All"
	_group_panel.visible = false


# Group stance: shows the shared stance name when the group agrees, otherwise
# "Mixed". Cycling steps every unit forward by one — convergence happens after
# at most 3 presses regardless of starting state.
func _group_stance_label(units: Array) -> String:
	if units.is_empty():
		return "—"
	var first_name: String = (units[0] as Unit).stance_name()
	for u in units:
		if (u as Unit).stance_name() != first_name:
			return "Mixed"
	return first_name


func _on_group_stance_pressed() -> void:
	for u in _selected_group:
		(u as Unit).cycle_stance()
	_group_stance_btn.text = "Stance: %s" % _group_stance_label(_selected_group)


# ── Inventory panel ───────────────────────────────────────────────────────────

func show_inventory_panel(title: String, inventory: Dictionary, screen_pos: Vector2) -> void:
	_inv_title.text = title
	for child in _inv_rows.get_children():
		child.queue_free()
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		_inv_rows.add_child(empty)
	else:
		for item in inventory:
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(56, 56)
			slot.tooltip_text = item

			var overlay := Control.new()
			overlay.custom_minimum_size = Vector2(56, 56)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var icon := TextureRect.new()
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if ITEM_ICONS.has(item):
				var tex := load(ITEM_ICONS[item]) as Texture2D
				if tex:
					icon.texture = tex
			overlay.add_child(icon)

			var qty := Label.new()
			qty.text = "×" + str(inventory[item])
			qty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(qty)

			slot.add_child(overlay)
			_inv_rows.add_child(slot)
	_inv_panel.position = screen_pos + Vector2(8, 8)
	_inv_panel.visible = true


# ── Character inventory panel ─────────────────────────────────────────────────

func _get_item_icon(item: String) -> Texture2D:
	if ITEM_ICONS.has(item):
		return load(ITEM_ICONS[item]) as Texture2D
	return null


func _make_drag_preview(item: String, count: int) -> Control:
	const SIZE := 52.0
	const HALF := SIZE * 0.5
	# Root is zero-size at cursor origin; children are offset so their
	# centre lands on the cursor regardless of whether Godot resets the root position.
	var root := Control.new()
	var icon := TextureRect.new()
	icon.position = Vector2(-HALF, -HALF)
	icon.size = Vector2(SIZE, SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = _get_item_icon(item)
	root.add_child(icon)
	if count > 1:
		var lbl := Label.new()
		lbl.position = Vector2(-HALF, -HALF)
		lbl.size = Vector2(SIZE, SIZE)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.text = "×%d" % count
		root.add_child(lbl)
	return root


func _build_char_inv_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left   = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 0
	panel.offset_right  = 706
	panel.offset_bottom = -44
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var outer := VBoxContainer.new()

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	_char_inv_portrait = TextureRect.new()
	_char_inv_portrait.custom_minimum_size = Vector2(36, 36)
	_char_inv_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_char_inv_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_char_inv_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_char_inv_portrait)
	_char_inv_name_lbl = Label.new()
	_char_inv_name_lbl.text = "Inventory"
	_char_inv_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_inv_name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_char_inv_name_lbl)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.pressed.connect(_on_char_inv_close)
	header.add_child(close_btn)
	outer.add_child(header)
	outer.add_child(HSeparator.new())

	# Body: equipment left, inventory right
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)

	# --- Equipment section ---
	var equip_vbox := VBoxContainer.new()
	equip_vbox.custom_minimum_size = Vector2(170, 0)

	var equip_lbl := Label.new()
	equip_lbl.text = "Equipment"
	equip_vbox.add_child(equip_lbl)

	# 3×3 grid representing body silhouette
	var equip_grid := GridContainer.new()
	equip_grid.columns = 3
	equip_grid.add_theme_constant_override("h_separation", 2)
	equip_grid.add_theme_constant_override("v_separation", 2)

	const EQUIP_LAYOUT := ["", "Head", "", "L.Arm", "Body", "R.Arm", "", "Legs", ""]
	_char_inv_equip_slots.clear()
	for slot_name: String in EQUIP_LAYOUT:
		if slot_name == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(52, 52)
			equip_grid.add_child(spacer)
		elif slot_name == "Body":
			var body_panel := Panel.new()
			body_panel.custom_minimum_size = Vector2(52, 52)
			equip_grid.add_child(body_panel)
		else:
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(52, 52)
			slot.tooltip_text = slot_name
			var lbl := Label.new()
			lbl.text = slot_name
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(lbl)
			equip_grid.add_child(slot)
			_char_inv_equip_slots[slot_name] = slot

	equip_vbox.add_child(equip_grid)
	equip_vbox.add_child(HSeparator.new())

	_char_inv_health_bar = _make_health_bar(160, 16)
	_char_inv_health_bar.tooltip_text = "Health"
	equip_vbox.add_child(_char_inv_health_bar)

	body.add_child(equip_vbox)
	body.add_child(VSeparator.new())

	# --- Inventory grid (2 rows × 10 cols) ---
	var inv_vbox := VBoxContainer.new()
	inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inv_lbl := Label.new()
	inv_lbl.text = "Inventory (20 slots)"
	inv_vbox.add_child(inv_lbl)

	_char_inv_grid = GridContainer.new()
	_char_inv_grid.columns = 10
	_char_inv_grid.add_theme_constant_override("h_separation", 2)
	_char_inv_grid.add_theme_constant_override("v_separation", 2)
	_char_inv_drop_slots.clear()
	for i in 20:
		var drop_slot := _InvDropSlot.new(self, i)
		_char_inv_grid.add_child(drop_slot)
		_char_inv_drop_slots.append(drop_slot)
	inv_vbox.add_child(_char_inv_grid)

	body.add_child(inv_vbox)
	outer.add_child(body)

	outer.add_child(HSeparator.new())
	var heal_btn := Button.new()
	heal_btn.text = "Heal"
	heal_btn.pressed.connect(_on_heal_button_pressed)
	outer.add_child(heal_btn)

	# Medic-only auto-heal toggle. Hidden on non-medic units in _refresh.
	_auto_heal_btn = Button.new()
	_auto_heal_btn.text = "Auto-heal: OFF"
	_auto_heal_btn.pressed.connect(_on_auto_heal_toggle)
	outer.add_child(_auto_heal_btn)

	panel.add_child(outer)
	return panel


func _on_auto_heal_toggle() -> void:
	if _char_inv_unit == null or not is_instance_valid(_char_inv_unit):
		return
	_char_inv_unit.auto_heal_enabled = not _char_inv_unit.auto_heal_enabled
	_refresh_auto_heal_button()


func _refresh_auto_heal_button() -> void:
	if _auto_heal_btn == null:
		return
	if _char_inv_unit == null or _char_inv_unit.data.role != "Medic":
		_auto_heal_btn.visible = false
		return
	_auto_heal_btn.visible = true
	_auto_heal_btn.text = "Auto-heal: ON" if _char_inv_unit.auto_heal_enabled else "Auto-heal: OFF"


# Heal flow: opened from the char-inv "Heal" button. The actor is whoever's
# inventory is currently shown. The flow asks: self or someone else? then which
# medicine? then applies the heal and decrements the item from the actor.
func _build_heal_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -160
	panel.offset_top    = -120
	panel.offset_right  = 160
	panel.offset_bottom = 120
	panel.custom_minimum_size = Vector2(320, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	_heal_title_lbl = Label.new()
	_heal_title_lbl.text = "Heal"
	_heal_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heal_title_lbl)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(28, 0)
	close.pressed.connect(_close_heal_panel)
	header.add_child(close)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	_heal_body = VBoxContainer.new()
	_heal_body.add_theme_constant_override("separation", 4)
	_heal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_heal_body)

	panel.add_child(vbox)
	return panel


func _on_heal_button_pressed() -> void:
	if _char_inv_unit == null or not is_instance_valid(_char_inv_unit):
		return
	if _char_inv_unit.is_dead():
		return
	_heal_actor = _char_inv_unit
	_heal_target = null
	_heal_state = 1
	_refresh_heal_panel()
	_heal_panel.visible = true


func _close_heal_panel() -> void:
	_heal_panel.visible = false
	_heal_state = 0
	_heal_actor = null
	_heal_target = null


func _refresh_heal_panel() -> void:
	# Clear body
	for child in _heal_body.get_children():
		child.queue_free()
	if _heal_actor == null or not is_instance_valid(_heal_actor):
		_close_heal_panel()
		return

	match _heal_state:
		1:
			_heal_title_lbl.text = "Heal — %s" % _heal_actor.data.name
			var self_btn := Button.new()
			self_btn.text = "Heal Self"
			self_btn.pressed.connect(func(): _heal_state = 2; _refresh_heal_panel())
			_heal_body.add_child(self_btn)
			var other_btn := Button.new()
			other_btn.text = "Heal Someone Else"
			other_btn.pressed.connect(func(): _heal_state = 3; _refresh_heal_panel())
			_heal_body.add_child(other_btn)
		2:
			_heal_title_lbl.text = "Pick medicine — heal %s" % _heal_actor.data.name
			_populate_heal_item_buttons(_heal_actor)
			_add_heal_back_button(1)
		3:
			_heal_title_lbl.text = "Pick someone to heal"
			var any: bool = false
			for u in _all_units:
				if u == null or not is_instance_valid(u) or u == _heal_actor:
					continue
				if (u as Unit).is_dead():
					continue
				any = true
				var b := Button.new()
				b.text = "%s — %d / %d HP" % [
					(u as Unit).data.name,
					int((u as Unit).data.health),
					int((u as Unit).data.max_health),
				]
				b.pressed.connect(func(): _heal_target = u; _heal_state = 4; _refresh_heal_panel())
				_heal_body.add_child(b)
			if not any:
				var lbl := Label.new()
				lbl.text = "(no one else available)"
				_heal_body.add_child(lbl)
			_add_heal_back_button(1)
		4:
			if _heal_target == null or not is_instance_valid(_heal_target):
				_heal_state = 3
				_refresh_heal_panel()
				return
			_heal_title_lbl.text = "Pick medicine — heal %s" % _heal_target.data.name
			_populate_heal_item_buttons(_heal_actor)
			_add_heal_back_button(3)
		_:
			_close_heal_panel()


func _populate_heal_item_buttons(actor: Unit) -> void:
	var any: bool = false
	for item: String in HEAL_AMOUNTS.keys():
		var count: int = int(actor.data.inventory.get(item, 0))
		if count <= 0:
			continue
		any = true
		var base_amount: float = float(HEAL_AMOUNTS[item])
		var amount: float = base_amount
		if actor.data.role == "Medic":
			amount *= MEDIC_HEAL_MULT
		var b := Button.new()
		b.text = "%s ×%d  (+%d HP%s)" % [
			item, count, int(amount),
			"  medic bonus" if actor.data.role == "Medic" else "",
		]
		var item_name: String = item
		var heal_amount: float = amount
		b.pressed.connect(func(): _apply_heal_item(item_name, heal_amount))
		_heal_body.add_child(b)
	if not any:
		var lbl := Label.new()
		lbl.text = "(no medicine in inventory)"
		_heal_body.add_child(lbl)


func _add_heal_back_button(prev_state: int) -> void:
	var sep := HSeparator.new()
	_heal_body.add_child(sep)
	var back := Button.new()
	back.text = "← Back"
	var prev: int = prev_state
	back.pressed.connect(func(): _heal_state = prev; _heal_target = null; _refresh_heal_panel())
	_heal_body.add_child(back)


func _apply_heal_item(item: String, amount: float) -> void:
	if _heal_actor == null or not is_instance_valid(_heal_actor):
		_close_heal_panel()
		return
	var target: Unit = _heal_target if _heal_target != null else _heal_actor
	if not is_instance_valid(target) or target.is_dead():
		_close_heal_panel()
		return
	var inv: Dictionary = _heal_actor.data.inventory
	var have: int = int(inv.get(item, 0))
	if have <= 0:
		_refresh_heal_panel()
		return
	var healed: float = target.apply_heal(amount)
	if healed <= 0.0:
		# Target already at full HP — don't waste the item.
		_refresh_heal_panel()
		return
	inv[item] = have - 1
	if inv[item] <= 0:
		inv.erase(item)
	_refresh_char_inv_panel()
	_close_heal_panel()


func _build_loot_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	# Free-floating: no anchors, positioned by show_loot_panel
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0
	panel.custom_minimum_size = Vector2(360, 0)

	var vbox := VBoxContainer.new()

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	# Drag logic on the header
	var drag_state := [false, Vector2.ZERO]  # [dragging, offset]
	header.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			drag_state[0] = event.pressed
			if drag_state[0]:
				drag_state[1] = panel.global_position - event.global_position
			header.get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and drag_state[0]:
			panel.global_position = event.global_position + drag_state[1]
			header.get_viewport().set_input_as_handled()
	)
	_loot_title_lbl = Label.new()
	_loot_title_lbl.text = "Loot"
	_loot_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_loot_title_lbl)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.pressed.connect(_on_loot_close)
	header.add_child(close_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	_loot_grid = GridContainer.new()
	_loot_grid.columns = 5
	_loot_grid.add_theme_constant_override("h_separation", 2)
	_loot_grid.add_theme_constant_override("v_separation", 2)
	_loot_drop_slots.clear()
	for i in 10:
		var slot := _LootDropSlot.new(self)
		_loot_grid.add_child(slot)
		_loot_drop_slots.append(slot)
	vbox.add_child(_loot_grid)

	vbox.add_child(HSeparator.new())
	var loot_all_btn := Button.new()
	loot_all_btn.text = "Loot All"
	loot_all_btn.pressed.connect(_on_loot_all_pressed)
	vbox.add_child(loot_all_btn)

	panel.add_child(vbox)
	return panel


# ── Wave banner ──────────────────────────────────────────────────────────────

# Top-center pill: main line shows wave state ("PEACE — Wave 2 in 42s",
# "WAVE 2 — incoming!", "EVAC — reach the marker"). Sub line shows transient
# announcements emitted by WaveManager.banner_message (auto-fades after duration).
func _build_wave_banner() -> void:
	_wave_banner = PanelContainer.new()
	_wave_banner.anchor_left = 0.0
	_wave_banner.anchor_right = 0.0
	_wave_banner.anchor_top = 0.0
	_wave_banner.anchor_bottom = 0.0
	# Top-left HUD column. Wave banner sits at the very top-left so the
	# player's eye lands on it first; disturbance bar + quest objective
	# stack underneath.
	_wave_banner.offset_left = 12
	_wave_banner.offset_right = 292
	_wave_banner.offset_top = 12
	_wave_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_banner.z_index = 50
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_banner_main_lbl = Label.new()
	_wave_banner_main_lbl.text = "—"
	_wave_banner_main_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner_main_lbl.add_theme_font_size_override("font_size", 14)
	_wave_banner_main_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_wave_banner_main_lbl)
	# Vague "wave is approaching" indicator: fills 0→100% over PEACE_DURATION.
	# No numeric label — the player reads tension from the bar's fullness, not
	# a clock. Hidden during WAVE / EVAC / endgame states.
	_wave_banner_progress = ProgressBar.new()
	_wave_banner_progress.show_percentage = false
	_wave_banner_progress.custom_minimum_size = Vector2(0, 6)
	_wave_banner_progress.min_value = 0.0
	_wave_banner_progress.max_value = 1.0
	_wave_banner_progress.value = 0.0
	_wave_banner_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_wave_banner_progress)
	_wave_banner_sub_lbl = Label.new()
	_wave_banner_sub_lbl.text = ""
	_wave_banner_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner_sub_lbl.add_theme_font_size_override("font_size", 11)
	_wave_banner_sub_lbl.modulate = Color(1.0, 0.92, 0.55, 1.0)
	_wave_banner_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_wave_banner_sub_lbl)
	_wave_banner.add_child(vbox)
	add_child(_wave_banner)
	_build_threat_panel()
	_build_quest_panel()


# Disturbance bar — sits just below the wave banner. Visible feedback for
# the action-driven wave-difficulty system: as the player harvests, mines,
# and builds, the bar fills, and the wave generator reads it to scale
# spawn density + creature variety. Color shifts green → yellow → red as
# the threat climbs so the player can read intensity at a glance.
func _build_threat_panel() -> void:
	_threat_panel = PanelContainer.new()
	# Top-left HUD column — sits directly under the wave banner.
	_threat_panel.anchor_left = 0.0
	_threat_panel.anchor_right = 0.0
	_threat_panel.anchor_top = 0.0
	_threat_panel.anchor_bottom = 0.0
	_threat_panel.offset_left = 12
	_threat_panel.offset_right = 292
	_threat_panel.offset_top = 80
	_threat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_panel.z_index = 50

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_threat_label = Label.new()
	_threat_label.text = "Disturbance"
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_label.add_theme_font_size_override("font_size", 10)
	_threat_label.modulate = Color(0.92, 0.92, 0.95, 0.85)
	_threat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_threat_label)

	_threat_bar = ProgressBar.new()
	_threat_bar.show_percentage = false
	_threat_bar.custom_minimum_size = Vector2(0, 8)
	_threat_bar.min_value = 0.0
	_threat_bar.max_value = THREAT_BAR_MAX
	_threat_bar.value = 0.0
	_threat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_threat_bar)

	_threat_panel.add_child(col)
	add_child(_threat_panel)


# Quest / objective panel — the third row in the top-left HUD column. Lists
# the step-by-step path from "just landed" to "called the shuttle." Updates
# every frame from game state: completed steps render dim with a check,
# the active step is highlighted bright, future steps are dim and unchecked.
func _build_quest_panel() -> void:
	_quest_panel = PanelContainer.new()
	_quest_panel.anchor_left = 0.0
	_quest_panel.anchor_right = 0.0
	_quest_panel.anchor_top = 0.0
	_quest_panel.anchor_bottom = 0.0
	_quest_panel.offset_left = 12
	_quest_panel.offset_right = 292
	_quest_panel.offset_top = 116
	_quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_panel.z_index = 50

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hdr := Label.new()
	hdr.text = "Objective"
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.modulate = Color(0.92, 0.92, 0.95, 0.85)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hdr)

	# RichTextLabel rather than Label so the per-step color spans (active /
	# done / upcoming) render via BBCode. fit_content makes the panel grow
	# to fit the lines without a scrollbar.
	_quest_lbl = RichTextLabel.new()
	_quest_lbl.bbcode_enabled = true
	_quest_lbl.fit_content = true
	_quest_lbl.scroll_active = false
	_quest_lbl.add_theme_font_size_override("normal_font_size", 11)
	_quest_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_quest_lbl)

	_quest_panel.add_child(col)
	add_child(_quest_panel)


# Read game state and render the objective list. Each step is one line
# prefixed with [✓] for done, [→] for active, or [ ] for upcoming. The
# active line gets a brighter color; everything else is dim.
func _tick_quest_panel() -> void:
	if _quest_lbl == null or grid == null:
		return
	var main_node: Node = grid.get_parent()
	if main_node == null:
		return
	# Detect game-state milestones in dependency order. The "active" step is
	# the first one not yet completed; everything before it is done.
	var has_fabricator: bool = not grid.fabricators.is_empty()
	var has_module: bool = false
	for u in main_node.all_units:
		if not is_instance_valid(u):
			continue
		var unit_node: Unit = u as Unit
		if int(unit_node.data.inventory.get("Comm Relay Module", 0)) > 0:
			has_module = true
			break
	# A relay counts as "built" when it appears in grid.comm_relays. Any
	# active channel is detected via the relay's `progress` and `completed`
	# fields.
	var has_relay: bool = not grid.comm_relays.is_empty()
	var channeling: bool = false
	var channel_done: bool = false
	for anchor in grid.comm_relays.keys():
		var relay: Dictionary = grid.comm_relays[anchor]
		if relay.get("completed", false):
			channel_done = true
			break
		if relay.get("channeler") != null:
			channeling = true
	# EVAC active means the rescue shuttle is in the world and units need
	# to walk to it. Mirrors WaveManager.State.EVAC = 2.
	var evac_active: bool = false
	if main_node.wave_manager != null and "state" in main_node.wave_manager:
		evac_active = int(main_node.wave_manager.state) == 2

	var steps: Array = [
		{"text": "Build a Fabricator",            "done": has_fabricator},
		{"text": "Craft a Comm Relay Module",     "done": has_module or has_relay},
		{"text": "Build a Comm Relay Antenna",    "done": has_relay},
		{"text": "Channel the relay (defend it!)","done": channel_done or evac_active, "active_extra": channeling},
		{"text": "Reach the rescue shuttle",      "done": false, "active_extra": evac_active},
	]
	# Active step = first not-done; or whichever step explicitly set
	# active_extra (e.g. channeling is mid-flight, evac is mid-flight).
	var active_idx: int = -1
	for i in steps.size():
		if not bool(steps[i].get("done", false)):
			active_idx = i
			break
	# Promote the active_extra override (used when "done" stays false but
	# we want the line highlighted as the player's current focus).
	for i in steps.size():
		if bool(steps[i].get("active_extra", false)):
			active_idx = i

	var lines: Array = []
	for i in steps.size():
		var s: Dictionary = steps[i]
		var done: bool = bool(s.get("done", false))
		var prefix: String
		if done:
			prefix = "[✓] "
		elif i == active_idx:
			prefix = "[→] "
		else:
			prefix = "[ ] "
		var line: String = prefix + String(s.text)
		# Use BBCode color spans so each line shades independently in a
		# single Label. Active = bright green; done = dim grey-green;
		# upcoming = neutral dim.
		var col: String
		if i == active_idx:
			col = "#7fff9c"
		elif done:
			col = "#6f9080"
		else:
			col = "#8a8a92"
		lines.append("[color=%s]%s[/color]" % [col, line])
	_quest_lbl.text = "\n".join(lines)


# Refresh per frame from Main.threat_level. Color cues:
#   0..40  → calm green
#   40..70 → yellow caution
#   70+    → red critical
# Bar saturates at THREAT_BAR_MAX so the readout stays meaningful even
# late game when threat keeps climbing past max.
func _tick_threat_bar() -> void:
	if _threat_bar == null:
		return
	var main_node: Node = grid.get_parent() if grid != null else null
	if main_node == null or not "threat_level" in main_node:
		return
	var t: float = float(main_node.threat_level)
	_threat_bar.value = clamp(t, 0.0, THREAT_BAR_MAX)
	var fill_col: Color
	if t < 40.0:
		fill_col = Color(0.35, 0.85, 0.45)  # calm green
	elif t < 70.0:
		fill_col = Color(0.95, 0.80, 0.30)  # caution yellow
	else:
		fill_col = Color(1.0, 0.40, 0.40)   # critical red
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill_col
	_threat_bar.add_theme_stylebox_override("fill", sb)
	# Label hint matches the color band so the text reinforces the bar's
	# state without the player needing to interpret a percentage.
	if t < 40.0:
		_threat_label.text = "Disturbance — calm"
	elif t < 70.0:
		_threat_label.text = "Disturbance — rising"
	else:
		_threat_label.text = "Disturbance — critical"


# Fullscreen modal shown on VICTORY / DEFEAT. Hidden by default. Centers a
# title label + two action buttons (Restart / Main Menu) so the player has a
# way out of the run instead of being stuck on the result screen.
func _build_endgame_overlay() -> void:
	_endgame_overlay = ColorRect.new()
	_endgame_overlay.color = Color(0.0, 0.0, 0.0, 0.78)
	_endgame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_endgame_overlay.visible = false
	_endgame_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_endgame_overlay.z_index = 100

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_endgame_overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	_endgame_label = Label.new()
	_endgame_label.text = ""
	_endgame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endgame_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_endgame_label.add_theme_font_size_override("font_size", 48)
	col.add_child(_endgame_label)

	# Stats panel — populated on victory/defeat with the frozen run_stats
	# dict. Sits between the title and the action buttons so the player
	# reads "VICTORY" → their run summary → Restart / Main Menu.
	_endgame_stats_lbl = Label.new()
	_endgame_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endgame_stats_lbl.add_theme_font_size_override("font_size", 14)
	_endgame_stats_lbl.modulate = Color(0.92, 0.92, 0.95, 0.95)
	_endgame_stats_lbl.text = ""
	col.add_child(_endgame_stats_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.custom_minimum_size = Vector2(160, 44)
	restart_btn.pressed.connect(_on_endgame_restart)
	btn_row.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(160, 44)
	menu_btn.pressed.connect(_on_endgame_main_menu)
	btn_row.add_child(menu_btn)

	add_child(_endgame_overlay)


# Reload the Main scene from scratch — fresh world, fresh wave timer, fresh
# inventories. Skips the save system entirely (this is a "play again" path,
# not a "load from disk" path).
func _on_endgame_restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_endgame_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# Connected to WaveManager.banner_message — temporary announcement on the sub line.
func show_wave_banner(text: String, duration: float) -> void:
	_wave_msg_text = text
	_wave_msg_timer = duration
	if _wave_banner_sub_lbl != null:
		_wave_banner_sub_lbl.text = text
		_wave_banner_sub_lbl.modulate = Color(1.0, 0.92, 0.55, 1.0)


# Connected to EventManager.event_announced — same banner slot as wave
# announcements but tinted to match the event color so the player can
# distinguish a Crab Raid from a Supply Drop at a glance.
func show_event_banner(event_name: String, color: Color, duration: float) -> void:
	_wave_msg_text = event_name
	_wave_msg_timer = duration
	if _wave_banner_sub_lbl != null:
		_wave_banner_sub_lbl.text = event_name
		_wave_banner_sub_lbl.modulate = color


# Lightning storm visual: a stuttering blue-white tint flashing across the
# whole canvas via CanvasModulate, plus a brief overlay rect on the GUI for
# extra punch. Fades to normal over `duration`.
var _lightning_t: float = 0.0
var _lightning_total: float = 0.0
var _lightning_overlay: ColorRect = null
# Strike state — when triggered, holds the flash for STRIKE_FADE seconds and
# fades out smoothly. Without this the previous "set color this frame" hack
# read as a strobe instead of distinct lightning flashes.
var _lightning_strike_t: float = 0.0
var _lightning_strike_next: float = 0.0
const _LIGHTNING_STRIKE_FADE: float = 0.22  # how long a single flash lingers
const _LIGHTNING_STRIKE_MIN: float = 1.5    # min seconds between strikes
const _LIGHTNING_STRIKE_MAX: float = 3.0    # max seconds between strikes

func trigger_lightning_storm(duration: float = 4.0) -> void:
	_lightning_t = duration
	_lightning_total = duration
	# Schedule the first strike a beat after the storm starts so the player
	# notices the dim ambient first.
	_lightning_strike_next = randf_range(0.5, 1.5)
	_lightning_strike_t = 0.0
	if _lightning_overlay == null:
		_lightning_overlay = ColorRect.new()
		_lightning_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_lightning_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lightning_overlay.z_index = 90
		_lightning_overlay.color = Color(0, 0, 0, 0)
		add_child(_lightning_overlay)


func _tick_lightning_storm(delta: float) -> void:
	if _lightning_t <= 0.0:
		if _lightning_overlay != null:
			_lightning_overlay.color = Color(0, 0, 0, 0)
		return
	_lightning_t -= delta
	if _lightning_overlay == null:
		return
	# Two layers: a slowly-pulsing dim blue ambient (storm clouds) + the
	# occasional bright strike that lingers + fades. Sparse strikes mean
	# the player feels each lightning hit as an event, not noise.
	var storm_progress: float = clamp(_lightning_t / _lightning_total, 0.0, 1.0)
	var ambient_pulse: float = 0.5 + sin(Time.get_ticks_msec() * 0.0025) * 0.5
	var ambient_alpha: float = 0.10 + 0.10 * ambient_pulse  # 0.10 → 0.20
	ambient_alpha *= storm_progress  # storm fades out toward the end
	var ambient_col := Color(0.20, 0.26, 0.42, ambient_alpha)

	# Schedule the next strike.
	_lightning_strike_next -= delta
	if _lightning_strike_next <= 0.0:
		_lightning_strike_t = _LIGHTNING_STRIKE_FADE
		_lightning_strike_next = randf_range(_LIGHTNING_STRIKE_MIN, _LIGHTNING_STRIKE_MAX)

	# Active strike fades smoothly from full bright → 0 over STRIKE_FADE.
	if _lightning_strike_t > 0.0:
		_lightning_strike_t -= delta
		var strike_k: float = clamp(_lightning_strike_t / _LIGHTNING_STRIKE_FADE, 0.0, 1.0)
		# Blend strike + ambient so the strike "tops up" the existing tint
		# rather than flashing independently.
		var strike_alpha: float = 0.55 * strike_k
		_lightning_overlay.color = ambient_col.lerp(Color(0.92, 0.96, 1.0, strike_alpha), strike_k)
	else:
		_lightning_overlay.color = ambient_col

	if _lightning_t <= 0.0:
		_lightning_overlay.color = Color(0, 0, 0, 0)
		_lightning_strike_t = 0.0


# Connected to WaveManager.state_changed — caches the state so the per-frame
# tick can render the right main-line text + countdown.
func on_wave_state_changed(new_state: int, wave_index: int, _duration: float) -> void:
	_wave_state = new_state
	_wave_index = wave_index
	# Mirror WaveManager.State enum: 0=PEACE 1=WAVE 2=EVAC 3=VICTORY 4=DEFEAT.
	if new_state == 3:
		_endgame_label.text = "VICTORY\nSurvivors evacuated"
		_endgame_label.modulate = Color(0.5, 1.0, 0.55)
		_endgame_overlay.visible = true
	elif new_state == 4:
		_endgame_label.text = "DEFEAT\nAll survivors lost"
		_endgame_label.modulate = Color(1.0, 0.45, 0.45)
		_endgame_overlay.visible = true


func _refresh_wave_banner_text() -> void:
	if _wave_banner_main_lbl == null:
		return
	var wm: Node = get_tree().root.get_node_or_null("Main/WaveManager")
	var progress: float = 0.0
	if wm != null and wm.has_method("get_phase_progress"):
		progress = wm.get_phase_progress()
	match _wave_state:
		0: # PEACE
			# Vague tier label so the player feels tension without seeing a clock.
			# Tiers reshape the player's perception: "distant" = relax and explore,
			# "imminent" = stop building, get into position.
			var tier: String
			if progress < 0.30:
				tier = "distant"
			elif progress < 0.60:
				tier = "approaching"
			elif progress < 0.85:
				tier = "soon"
			else:
				tier = "imminent"
			_wave_banner_main_lbl.text = "PEACE — Wave %d %s" % [_wave_index, tier]
			# Banner color shifts toward red as the wave nears.
			var warn: float = clamp((progress - 0.5) * 2.0, 0.0, 1.0)
			_wave_banner_main_lbl.modulate = Color(0.65, 0.95, 0.75).lerp(Color(1.0, 0.7, 0.45), warn)
			if _wave_banner_progress != null:
				_wave_banner_progress.visible = true
				_wave_banner_progress.value = progress
		1: # WAVE
			_wave_banner_main_lbl.text = "WAVE %d" % _wave_index
			_wave_banner_main_lbl.modulate = Color(1.0, 0.55, 0.45)
			if _wave_banner_progress != null:
				_wave_banner_progress.visible = false
		2: # EVAC
			# Show the rescue countdown + boarded counter so the player knows
			# both how much time is left and how many survivors remain.
			var remaining_s: float = 0.0
			if wm != null and wm.has_method("get_phase_remaining"):
				remaining_s = wm.get_phase_remaining()
			var mm: int = int(remaining_s) / 60
			var ss: int = int(remaining_s) % 60
			var boarded: int = 0
			var stragglers: int = 0
			if wm != null and wm.has_method("get_evac_boarded"):
				boarded = wm.get_evac_boarded()
				stragglers = wm.get_evac_remaining()
			var total: int = boarded + stragglers
			_wave_banner_main_lbl.text = "EVAC %d:%02d  —  %d / %d boarded" % [mm, ss, boarded, max(total, 1)]
			# Color shifts green → red as the deadline approaches.
			var urgency: float = clamp(progress, 0.0, 1.0)
			_wave_banner_main_lbl.modulate = Color(0.45, 1.0, 0.65).lerp(Color(1.0, 0.4, 0.4), urgency)
			if _wave_banner_progress != null:
				_wave_banner_progress.visible = true
				_wave_banner_progress.value = progress
		3: # VICTORY
			_wave_banner_main_lbl.text = "VICTORY"
			_wave_banner_main_lbl.modulate = Color(0.65, 1.0, 0.65)
			if _wave_banner_progress != null:
				_wave_banner_progress.visible = false
			_populate_endgame_stats()
		4: # DEFEAT
			_wave_banner_main_lbl.text = "DEFEAT"
			_wave_banner_main_lbl.modulate = Color(1.0, 0.4, 0.4)
			if _wave_banner_progress != null:
				_wave_banner_progress.visible = false
			_populate_endgame_stats()


# Reads the frozen run_stats dict off Main and renders it as a multiline
# block on the endgame overlay. Called once when victory or defeat fires;
# fields not yet implemented show a `—` placeholder rather than a 0.
func _populate_endgame_stats() -> void:
	if _endgame_stats_lbl == null:
		return
	var main_node: Node = grid.get_parent() if grid != null else null
	if main_node == null or not "run_stats" in main_node:
		return
	var s: Dictionary = main_node.run_stats
	var t: float = float(s.get("run_time", 0.0))
	var mm: int = int(t) / 60
	var ss: int = int(t) % 60
	var lines: Array = [
		"Run time:           %d:%02d" % [mm, ss],
		"Waves completed:    %d / 3" % int(s.get("waves_completed", 0)),
		"Enemy kills:        %d" % int(s.get("kills", 0)),
		"Trees harvested:    %d" % int(s.get("trees_harvested", 0)),
		"Rocks / ores mined: %d" % int(s.get("rocks_mined", 0)),
		"Items crafted:      %d" % int(s.get("items_crafted", 0)),
		"Buildings built:    %d" % int(s.get("buildings_built", 0)),
		"Survivors downed:   %d" % int(s.get("downed_count", 0)),
		"Revives performed:  %d" % int(s.get("revived_count", 0)),
	]
	var decisions: Array = s.get("decisions", [])
	if not decisions.is_empty():
		lines.append("")
		lines.append("Choices that shaped the run:")
		for d in decisions:
			lines.append("  • " + str(d))
	_endgame_stats_lbl.text = "\n".join(lines)


const LOOT_TOAST_SCRIPT: Script = preload("res://scripts/ui/LootToast.gd")


# Spawn floating "+N item" notifications above a kill site, one stacked toast
# per item type. Toasts are world-space Node2Ds parented to Main so they
# follow the camera naturally; they self-destruct after their fade animation.
# Called from Crab._drop_loot when a wave kill yields loot.
func notify_loot_batch(world_pos: Vector2, drops: Dictionary) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null or drops.is_empty():
		return
	var idx: int = 0
	for item_name: String in drops.keys():
		var count: int = int(drops[item_name])
		if count <= 0:
			continue
		var t := Node2D.new()
		t.set_script(LOOT_TOAST_SCRIPT)
		main.add_child(t)
		# Stack vertically so multiple drops from one kill don't overlap.
		t.position = world_pos + Vector2(0.0, -float(idx) * 22.0)
		var icon: Texture2D = null
		if ITEM_ICONS.has(item_name):
			icon = load(ITEM_ICONS[item_name]) as Texture2D
		var text: String = ("+%d %s" % [count, item_name]) if count > 1 else ("+%s" % item_name)
		t.setup(icon, text)
		idx += 1


# Show "Need N Item" red toasts above a target — used when a Build command
# can't dispatch yet because the team is short on materials. Same component
# as loot toasts, just tinted red and prefixed with "Need" so the player
# immediately reads it as a shortage warning rather than a gain.
func notify_shortage(world_pos: Vector2, missing: Dictionary) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null or missing.is_empty():
		return
	const SHORTAGE_COLOR: Color = Color(1.0, 0.45, 0.45)
	var idx: int = 0
	for item_name: String in missing.keys():
		var count: int = int(missing[item_name])
		if count <= 0:
			continue
		var t := Node2D.new()
		t.set_script(LOOT_TOAST_SCRIPT)
		main.add_child(t)
		t.position = world_pos + Vector2(0.0, -float(idx) * 22.0)
		var icon: Texture2D = null
		if ITEM_ICONS.has(item_name):
			icon = load(ITEM_ICONS[item_name]) as Texture2D
		var text: String = "Need %d %s" % [count, item_name]
		t.setup(icon, text, SHORTAGE_COLOR)
		idx += 1


func _tick_wave_banner(delta: float) -> void:
	_refresh_wave_banner_text()
	if _wave_msg_timer > 0.0 and _wave_banner_sub_lbl != null:
		_wave_msg_timer -= delta
		if _wave_msg_timer <= 0.0:
			_wave_banner_sub_lbl.text = ""
		elif _wave_msg_timer < 0.5:
			# Fade the announcement out in the last half-second.
			var a: float = _wave_msg_timer / 0.5
			_wave_banner_sub_lbl.modulate = Color(1.0, 0.92, 0.55, a)


func show_char_inv_panel(unit: Unit) -> void:
	_char_inv_unit = unit
	_refresh_char_inv_panel()
	_char_inv_panel.visible = true


func _refresh_char_inv_panel() -> void:
	if _char_inv_unit == null:
		return
	_char_inv_portrait.texture = _char_inv_unit.data.portrait
	_char_inv_name_lbl.text = _char_inv_unit.data.name
	_char_inv_health_bar.max_value = _char_inv_unit.data.max_health
	_char_inv_health_bar.value = _char_inv_unit.data.health
	_char_inv_health_bar.tooltip_text = "%d / %d HP" % [
		int(_char_inv_unit.data.health), int(_char_inv_unit.data.max_health)
	]
	for slot in _char_inv_drop_slots:
		(slot as _InvDropSlot).clear_item()
	var idx := 0
	for item: String in _char_inv_unit.data.inventory:
		if idx >= 20:
			break
		(_char_inv_drop_slots[idx] as _InvDropSlot).set_item(item, _char_inv_unit.data.inventory[item])
		idx += 1
	_refresh_auto_heal_button()


func show_loot_panel(title: String, source_inv: Dictionary, source_pos: Vector2) -> void:
	_loot_title_lbl.text = title
	_loot_source_inv = source_inv
	_loot_source_pos = source_pos
	_refresh_loot_panel()
	# Visible first so layout flushes; size is otherwise zero on the first frame.
	_loot_panel.visible = true
	_loot_panel.reset_size()
	# Loot panel's top-left corner sits exactly on the inventory panel's
	# top-right corner — touching, not overlapping. Falls back to a screen-edge
	# position if the inventory isn't open for some reason.
	var lp_size := _loot_panel.size
	if _char_inv_panel.visible:
		var inv_rect := _char_inv_panel.get_global_rect()
		_loot_panel.position = Vector2(
			inv_rect.position.x + inv_rect.size.x,
			inv_rect.position.y
		)
	else:
		var vp := get_viewport().get_visible_rect().size
		_loot_panel.position = Vector2(vp.x - lp_size.x - 8.0, 8.0)


func _refresh_loot_panel() -> void:
	var items := _loot_source_inv.keys()
	for i in _loot_drop_slots.size():
		var slot := _loot_drop_slots[i] as _LootDropSlot
		if i < items.size():
			slot.set_item(items[i], _loot_source_inv[items[i]])
		else:
			slot.clear_item()


func _on_unit_inv_btn_pressed() -> void:
	if _selected_unit == null:
		return
	hide_unit_panel()
	show_char_inv_panel(_selected_unit)


# Shortcut from the unit popup: skip the inventory and go straight to the
# heal flow, with the selected unit as the actor.
func _on_unit_panel_heal_pressed() -> void:
	if _selected_unit == null or not is_instance_valid(_selected_unit):
		return
	if _selected_unit.is_dead():
		return
	hide_unit_panel()
	_heal_actor = _selected_unit
	_heal_target = null
	_heal_state = 1
	_refresh_heal_panel()
	_heal_panel.visible = true


func _on_loot_all_pressed() -> void:
	if _char_inv_unit == null:
		return
	for item: String in _loot_source_inv.duplicate():
		_char_inv_unit.data.inventory[item] = _char_inv_unit.data.inventory.get(item, 0) + _loot_source_inv[item]
	_loot_source_inv.clear()
	_refresh_loot_panel()
	_refresh_char_inv_panel()


func _on_char_inv_close() -> void:
	_char_inv_panel.visible = false
	_loot_panel.visible = false
	_char_inv_unit = null
	if _heal_panel != null and _heal_panel.visible:
		_close_heal_panel()


func _on_loot_close() -> void:
	_loot_panel.visible = false


# ── Fabricator craft panel ─────────────────────────────────────────────────

func _build_craft_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0
	panel.custom_minimum_size = Vector2(420, 0)
	panel.z_index = 60

	var vbox := VBoxContainer.new()

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	# Drag the panel by its header so it can be repositioned out of the way.
	var drag_state := [false, Vector2.ZERO]
	header.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			drag_state[0] = event.pressed
			if drag_state[0]:
				drag_state[1] = panel.global_position - event.global_position
			header.get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and drag_state[0]:
			panel.global_position = event.global_position + drag_state[1]
			header.get_viewport().set_input_as_handled()
	)
	var title := Label.new()
	title.text = "Fabricator"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.pressed.connect(_on_craft_close)
	header.add_child(close_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# Scrollable recipe list (each entry rebuilt on _refresh_craft_panel).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	_craft_recipes_box = VBoxContainer.new()
	_craft_recipes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_craft_recipes_box)
	vbox.add_child(scroll)
	vbox.add_child(HSeparator.new())

	# Active queue section: progress bar + list of pending recipes.
	var queue_lbl := Label.new()
	queue_lbl.text = "Queue"
	vbox.add_child(queue_lbl)
	_craft_progress_bar = ProgressBar.new()
	_craft_progress_bar.min_value = 0.0
	_craft_progress_bar.max_value = 1.0
	_craft_progress_bar.value = 0.0
	_craft_progress_bar.show_percentage = false
	_craft_progress_bar.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(_craft_progress_bar)
	_craft_queue_box = VBoxContainer.new()
	vbox.add_child(_craft_queue_box)

	panel.add_child(vbox)
	return panel


func show_craft_panel(anchor: Vector2) -> void:
	_craft_anchor = anchor
	_refresh_craft_panel()
	_craft_panel.visible = true
	_craft_panel.reset_size()
	# Position near the centre-right of the viewport so it doesn't overlap
	# the unit HUD strip on the left.
	var vp_size: Vector2 = get_viewport_rect().size
	var p_size: Vector2 = _craft_panel.size
	_craft_panel.global_position = Vector2(vp_size.x - p_size.x - 24, 90)


func _on_craft_close() -> void:
	_craft_panel.visible = false
	_craft_anchor = Vector2(-1, -1)


# Toggle the fullscreen map overlay. When opened, the player can hover any
# marker for a tooltip and left-click anywhere to recenter the camera +
# auto-close. Outside-click and Esc also close (handled in _unhandled_input).
func _on_map_expand_pressed() -> void:
	if _map_panel == null:
		return
	_map_panel.visible = not _map_panel.visible


# ── Choice event modal ─────────────────────────────────────────────────────

# Built once at startup. Shown via show_choice_event whenever EventManager
# fires a branching event; hidden when the player picks an option (or when
# they click outside, after which the event silently auto-defaults to the
# first option to avoid soft-locking the run).
func _build_choice_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -160
	panel.offset_bottom = 160
	panel.z_index = 80
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_choice_title_lbl = Label.new()
	_choice_title_lbl.text = "Event"
	_choice_title_lbl.add_theme_font_size_override("font_size", 22)
	_choice_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_choice_title_lbl)

	_choice_desc_lbl = Label.new()
	_choice_desc_lbl.text = ""
	_choice_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_desc_lbl.modulate = Color(0.92, 0.92, 0.95)
	col.add_child(_choice_desc_lbl)

	col.add_child(HSeparator.new())

	_choice_btn_box = VBoxContainer.new()
	_choice_btn_box.add_theme_constant_override("separation", 6)
	col.add_child(_choice_btn_box)
	return panel


# Shown by EventManager when a branching event fires.
# `options` is an Array of { "label": String, "callback": Callable } entries.
# Each option's callback fires the gameplay consequence; the choice is logged
# to Main.run_stats.decisions via record_decision() for the summary panel.
func show_choice_event(event_name: String, description: String, options: Array) -> void:
	if _choice_panel == null:
		return
	_choice_pending_event = event_name
	_choice_title_lbl.text = event_name
	_choice_desc_lbl.text = description
	for c in _choice_btn_box.get_children():
		c.queue_free()
	for entry: Dictionary in options:
		var btn := Button.new()
		btn.text = String(entry.get("label", "Choose"))
		btn.custom_minimum_size = Vector2(0, 36)
		var label_text: String = String(entry.get("label", ""))
		var cb: Callable = entry.get("callback", Callable())
		btn.pressed.connect(func(): _on_choice_picked(label_text, cb))
		_choice_btn_box.add_child(btn)
	_choice_panel.visible = true


func _on_choice_picked(label_text: String, cb: Callable) -> void:
	_choice_panel.visible = false
	# Log the player's pick for the end-of-run summary so they can see how
	# their decisions shaped the run.
	var main_node: Node = grid.get_parent() if grid != null else null
	if main_node != null and main_node.has_method("record_decision"):
		main_node.record_decision(_choice_pending_event, label_text)
	_choice_pending_event = ""
	if cb.is_valid():
		cb.call()


# Rebuild the recipe list + queue from current state. Cheap enough to call
# every time the queue changes; live progress is updated separately in
# _process so the bar moves smoothly without flicker.
func _refresh_craft_panel() -> void:
	for c in _craft_recipes_box.get_children():
		c.queue_free()
	for c in _craft_queue_box.get_children():
		c.queue_free()

	# Recipes grouped by category. Each row: name + I/O summary + Queue button.
	for cat in _CRAFT_RECIPES_GUI.get_categories():
		var cat_lbl := Label.new()
		cat_lbl.text = cat
		cat_lbl.add_theme_font_size_override("font_size", 12)
		cat_lbl.modulate = Color(0.85, 0.85, 0.95)
		_craft_recipes_box.add_child(cat_lbl)
		for r: Dictionary in _CRAFT_RECIPES_GUI.by_category(cat):
			_craft_recipes_box.add_child(_build_craft_recipe_row(r))
		var sep := HSeparator.new()
		sep.modulate = Color(1, 1, 1, 0.3)
		_craft_recipes_box.add_child(sep)

	# Queue display.
	if _craft_anchor == Vector2(-1, -1) or not grid.fabricators.has(_craft_anchor):
		return
	var queue: Array = grid.fabricators[_craft_anchor].queue
	if queue.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(idle)"
		empty_lbl.modulate = Color(0.7, 0.7, 0.7)
		_craft_queue_box.add_child(empty_lbl)
		return
	for i in queue.size():
		var rec_id: String = queue[i]
		var rec: Dictionary = _CRAFT_RECIPES_GUI.find(rec_id)
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = ("▶ " if i == 0 else "• ") + str(rec.get("name", rec_id))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var cancel_btn := Button.new()
		cancel_btn.text = "×"
		cancel_btn.custom_minimum_size = Vector2(28, 0)
		var idx: int = i
		cancel_btn.pressed.connect(func(): _on_craft_cancel_pressed(idx))
		row.add_child(cancel_btn)
		_craft_queue_box.add_child(row)


func _build_craft_recipe_row(recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	# Output icon — the visual hook that tells the player what they get.
	var out_items: Dictionary = recipe.output
	var primary_out: String = ""
	for k in out_items.keys():
		primary_out = k
		break
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if primary_out != "" and ITEM_ICONS.has(primary_out):
		icon.texture = load(ITEM_ICONS[primary_out]) as Texture2D
	row.add_child(icon)

	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = recipe.name
	info_col.add_child(name_lbl)
	# Inputs → Outputs summary, plus craft time.
	var in_parts: Array = []
	for k in (recipe.inputs as Dictionary).keys():
		in_parts.append("%d× %s" % [int(recipe.inputs[k]), k])
	var out_parts: Array = []
	for k in out_items.keys():
		out_parts.append("%d× %s" % [int(out_items[k]), k])
	var io_lbl := Label.new()
	io_lbl.text = "%s → %s   (%ds)" % [", ".join(in_parts), ", ".join(out_parts), int(recipe.get("time", 0.0))]
	io_lbl.add_theme_font_size_override("font_size", 11)
	io_lbl.modulate = Color(0.78, 0.78, 0.82)
	info_col.add_child(io_lbl)
	row.add_child(info_col)

	var queue_btn := Button.new()
	queue_btn.text = "Queue"
	queue_btn.custom_minimum_size = Vector2(72, 0)
	# Disable when the team can't afford the recipe (not when in-progress —
	# you can queue duplicates to chain crafts).
	queue_btn.disabled = not _team_has_inputs(recipe.inputs)
	var rid: String = recipe.id
	queue_btn.pressed.connect(func(): _on_craft_queue_pressed(rid))
	row.add_child(queue_btn)
	return row


# Check team-pool inventory against the recipe's input dict. Mirrors
# Main.pull_shared_resources's first pass without committing the deduct.
func _team_has_inputs(inputs: Dictionary) -> bool:
	var main_node: Node = grid.get_parent()
	if main_node == null:
		return false
	for item_name in inputs.keys():
		var needed: int = int(inputs[item_name])
		var team_total: int = 0
		for u in main_node.all_units:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.is_dead() or unit_node.is_downed:
				continue
			team_total += int(unit_node.data.inventory.get(item_name, 0))
		if team_total < needed:
			return false
	return true


func _on_craft_queue_pressed(recipe_id: String) -> void:
	if _craft_anchor == Vector2(-1, -1):
		return
	if grid.queue_craft(_craft_anchor, recipe_id):
		_refresh_craft_panel()


func _on_craft_cancel_pressed(idx: int) -> void:
	if _craft_anchor == Vector2(-1, -1):
		return
	if grid.cancel_craft(_craft_anchor, idx):
		_refresh_craft_panel()


func on_item_dropped_to_inv(item: String, count: int, source_inv: Dictionary) -> void:
	if _char_inv_unit == null:
		return
	source_inv[item] -= count
	if source_inv[item] <= 0:
		source_inv.erase(item)
	_char_inv_unit.data.inventory[item] = _char_inv_unit.data.inventory.get(item, 0) + count
	_refresh_loot_panel()
	_refresh_char_inv_panel()


# ── Dialog panel ──────────────────────────────────────────────────────────────

func show_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = ""
	_dialog_text.visible = false
	_dialog_text_sep.visible = false
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func show_monolith_dialog(screen_pos: Vector2) -> void:
	_dialog_portrait.texture = null
	_dialog_name.text = "Ancient Monolith"
	_dialog_role.text = "Unknown Origin"
	_dialog_draft_btn.visible = false
	_dialog_text.text = '"' + MONOLITH_LINES[_dialog_rng.randi() % MONOLITH_LINES.size()] + '"'
	_dialog_text.visible = true
	_dialog_text_sep.visible = true
	_dialog_panel.position = screen_pos + Vector2(8, 8)
	_dialog_panel.visible = true


func _on_dialog_draft_pressed() -> void:
	pass


func _on_inspect_pressed() -> void:
	_dialog_panel.visible = false
	inspect_requested.emit()


# ── Top HUD (drafted units) ───────────────────────────────────────────────────

func _make_health_bar(w: float, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(w, h)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.75, 0.25)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_top_hud() -> void:
	# Top-center horizontal strip. Every live (non-evacuated) unit gets a
	# card here so the player can see the team at a glance and shift-click
	# to multi-select before drafting.
	var wrapper := CenterContainer.new()
	wrapper.anchor_left   = 0.0
	wrapper.anchor_right  = 1.0
	wrapper.anchor_top    = 0.0
	wrapper.anchor_bottom = 0.0
	wrapper.offset_top    = 6
	wrapper.offset_bottom = 76
	wrapper.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_top_hud = HBoxContainer.new()
	_top_hud.add_theme_constant_override("separation", 8)
	_top_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(_top_hud)
	add_child(wrapper)


func _refresh_top_hud(units: Array) -> void:
	_hud_bars.clear()
	for c in _top_hud.get_children():
		c.queue_free()
	for u in units:
		var u_node := u as Unit

		# Fixed-size square card. Border + background reflect state:
		#   default  → dark bg, thin white border
		#   drafted  → orange-tinted bg, orange border (matches the drafted
		#              ground-ring color so the visuals match in-world)
		#   selected → border thickens to 3px in the same color, so a card
		#              can be both drafted (orange) AND selected (thick).
		# Built on Button (not Panel) so press AND release are reliably
		# consumed by the GUI subsystem — `accept_event` on a Panel was
		# letting the release leak through to Main._handle_click on some
		# layouts, which deselected everything on every portrait click.
		var card := Button.new()
		card.custom_minimum_size = Vector2(56, 56)
		card.clip_contents = true
		card.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		if u_node.is_downed:
			# Pulsing-feel red border so a downed teammate jumps out as a
			# critical issue. Bg goes deep red so even a glance reads "out".
			style.bg_color = Color(0.35, 0.05, 0.05, 0.65)
			style.border_color = Color(1.0, 0.30, 0.30, 0.95)
		elif u_node.drafted:
			style.bg_color = Color(0.35, 0.18, 0.04, 0.55)
			style.border_color = Color(1.0, 0.55, 0.0, 0.95)
		else:
			style.bg_color = Color(0, 0, 0, 0.4)
			style.border_color = Color(1, 1, 1, 0.7)
		var border_w: int = 3 if u_node.selected else 1
		style.set_border_width_all(border_w)
		# Override every Button state so hover/pressed/disabled don't flash a
		# different visual — the card should look the same regardless.
		card.add_theme_stylebox_override("normal", style)
		card.add_theme_stylebox_override("hover", style)
		card.add_theme_stylebox_override("pressed", style)
		card.add_theme_stylebox_override("focus", style)
		card.add_theme_stylebox_override("disabled", style)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Plain click: select this unit only + center camera. Shift-click:
		# toggle membership in the selection so the player can build up a
		# multi-select before pressing R to draft them all. Shift state is
		# read at signal time via Input — Button.pressed doesn't carry it.
		card.pressed.connect(func():
			var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
			_on_portrait_clicked(u_node, shift_held)
		)

		# Portrait fills the whole card
		var portrait := TextureRect.new()
		portrait.anchor_right = 1.0
		portrait.anchor_bottom = 1.0
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if u_node.data.portrait:
			portrait.texture = u_node.data.portrait
		# Slightly desaturate undrafted portraits so drafted ones pop visually.
		# Downed portraits go further — heavily darkened with a red wash so
		# the player can tell at a glance someone needs help.
		if u_node.is_downed:
			portrait.modulate = Color(0.55, 0.30, 0.30, 1.0)
		elif not u_node.drafted:
			portrait.modulate = Color(0.85, 0.85, 0.85, 1.0)
		card.add_child(portrait)

		# Health bar pinned to bottom edge
		var bar := _make_health_bar(0, 5)
		bar.max_value = u_node.data.max_health
		bar.value = u_node.data.health
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = -5
		bar.offset_bottom = 0
		card.add_child(bar)
		_hud_bars[u] = bar

		# Name just above the bar
		var name_lbl := Label.new()
		name_lbl.text = u_node.data.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.anchor_left = 0.0
		name_lbl.anchor_right = 1.0
		name_lbl.anchor_top = 1.0
		name_lbl.anchor_bottom = 1.0
		name_lbl.offset_top = -19
		name_lbl.offset_bottom = -5
		card.add_child(name_lbl)

		_top_hud.add_child(card)


# Portrait click → update Main.selected_units. Plain click replaces the
# selection with just this unit (and centers the camera). Shift-click toggles
# this unit's membership in the existing selection without moving the camera.
func _on_portrait_clicked(u: Unit, shift_held: bool) -> void:
	var main_node: Node = grid.get_parent()
	if main_node == null:
		return
	if shift_held:
		var current: Array = (main_node.selected_units as Array).duplicate()
		if current.has(u):
			current.erase(u)
		else:
			current.append(u)
		main_node._set_selection(current)
	else:
		main_node._set_selection([u])
		camera.center_on(u.position)


# ── HUD ───────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_tick_wave_banner(_delta)
	_tick_lightning_storm(_delta)
	_tick_threat_bar()
	_tick_quest_panel()

	# Show every live, non-evacuated unit in the left-edge column. Drafted
	# and selected styling is applied inside _refresh_top_hud.
	var live: Array = []
	for u in grid.get_parent().get_node("Units").get_children():
		if u is Unit and not (u as Unit).is_dead() and not (u as Unit).evacuated:
			live.append(u)

	# Re-render only when something visible to the HUD changes — composition,
	# draft state, selection state, or downed flag. Each unit contributes a
	# tuple so any of those flipping triggers a re-render.
	var state: Array = live.map(func(u): return [u.get_instance_id(), u.drafted, u.selected, u.is_downed])
	if state != _last_drafted_ids:
		_last_drafted_ids = state
		_refresh_top_hud(live)

	# Update health bars live
	for u in _hud_bars:
		if is_instance_valid(u) and is_instance_valid(_hud_bars[u]):
			(_hud_bars[u] as ProgressBar).value = (u as Unit).data.health

	# Live craft panel updates: progress bar tracks the front of the queue,
	# and the panel auto-refreshes when a craft completes (queue length drops)
	# so the player sees their output land + the next recipe slide forward.
	if _craft_panel != null and _craft_panel.visible and _craft_anchor != Vector2(-1, -1) and grid.fabricators.has(_craft_anchor):
		var fab: Dictionary = grid.fabricators[_craft_anchor]
		var queue: Array = fab.queue
		if queue.is_empty():
			_craft_progress_bar.value = 0.0
			# If we cached a non-empty queue last frame and now it's empty
			# (a craft just finished), redraw to show the (idle) state.
			if _craft_queue_box.get_child_count() == 0 or _craft_queue_box.get_child(0) is HBoxContainer:
				_refresh_craft_panel()
		else:
			var rec: Dictionary = _CRAFT_RECIPES_GUI.find(queue[0])
			var total: float = float(rec.get("time", 1.0)) if not rec.is_empty() else 1.0
			_craft_progress_bar.value = clamp(float(fab.progress) / total, 0.0, 1.0)
			# When queue length changes (front popped on completion), refresh.
			if _craft_queue_box.get_child_count() != queue.size():
				_refresh_craft_panel()

	# Keep char inv health bar in sync
	if _char_inv_panel.visible and _char_inv_unit != null and is_instance_valid(_char_inv_unit):
		_char_inv_health_bar.value = _char_inv_unit.data.health


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	# Close bottom panels if click lands outside them
	if _construct_panel.visible:
		if not _construct_panel.get_global_rect().has_point(mb.global_position):
			_construct_panel.visible = false
			get_viewport().set_input_as_handled()
	elif _global_inv_panel.visible:
		if not _global_inv_panel.get_global_rect().has_point(mb.global_position):
			_global_inv_panel.visible = false
			get_viewport().set_input_as_handled()
	elif _units_panel.visible:
		if not _units_panel.get_global_rect().has_point(mb.global_position):
			_units_panel.visible = false
			get_viewport().set_input_as_handled()
	elif _work_panel != null and _work_panel.visible:
		if not _work_panel.get_global_rect().has_point(mb.global_position):
			_work_panel.visible = false
			get_viewport().set_input_as_handled()
	elif _orders_panel != null and _orders_panel.visible:
		if not _orders_panel.get_global_rect().has_point(mb.global_position):
			_orders_panel.visible = false
			get_viewport().set_input_as_handled()

	# Fabricator craft panel — close on outside-click. Right-click on the
	# fabricator to reopen. Floats free of the bottom strip so it gets its
	# own check rather than living in the elif chain above.
	if _craft_panel != null and _craft_panel.visible:
		if not _craft_panel.get_global_rect().has_point(mb.global_position):
			_on_craft_close()
			get_viewport().set_input_as_handled()

	# Close char inv / loot / heal panels if click lands outside all of them
	if _char_inv_panel.visible or _loot_panel.visible:
		var in_char := _char_inv_panel.visible and _char_inv_panel.get_global_rect().has_point(mb.global_position)
		var in_loot := _loot_panel.visible and _loot_panel.get_global_rect().has_point(mb.global_position)
		var in_heal := _heal_panel != null and _heal_panel.visible and _heal_panel.get_global_rect().has_point(mb.global_position)
		if not in_char and not in_loot and not in_heal:
			_on_char_inv_close()
			get_viewport().set_input_as_handled()
	# Heal panel can also be opened standalone from the unit popup — handle that
	# case (when the inventory is closed) independently.
	elif _heal_panel != null and _heal_panel.visible:
		if not _heal_panel.get_global_rect().has_point(mb.global_position):
			_close_heal_panel()
			get_viewport().set_input_as_handled()

	# Small popups: each closes when the click lands outside its rect. Independent
	# `if`s (not chained) so multiple stale popups all dismiss together.
	if _unit_panel.visible:
		if not _unit_panel.get_global_rect().has_point(mb.global_position):
			_unit_panel.visible = false
			get_viewport().set_input_as_handled()
	if _group_panel.visible:
		if not _group_panel.get_global_rect().has_point(mb.global_position):
			_group_panel.visible = false
			get_viewport().set_input_as_handled()
	if _tree_panel.visible:
		if not _tree_panel.get_global_rect().has_point(mb.global_position):
			_tree_panel.visible = false
			get_viewport().set_input_as_handled()
	if _dialog_panel.visible:
		if not _dialog_panel.get_global_rect().has_point(mb.global_position):
			_dialog_panel.visible = false
			get_viewport().set_input_as_handled()


# ── Draggable loot slot ───────────────────────────────────────────────────────

class _LootSlot extends PanelContainer:
	var _item_name: String
	var _count: int
	var _source_inv: Dictionary
	var _gui_ref  # GUI node reference for icon loading

	func _init(item: String, count: int, source: Dictionary, gui_node) -> void:
		_item_name = item
		_count = count
		_source_inv = source
		_gui_ref = gui_node
		custom_minimum_size = Vector2(52, 52)
		tooltip_text = "%s ×%d" % [item, count]
		mouse_default_cursor_shape = Control.CURSOR_DRAG

		var overlay := Control.new()
		overlay.custom_minimum_size = Vector2(52, 52)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _gui_ref != null:
			icon.texture = _gui_ref._get_item_icon(item)
		overlay.add_child(icon)

		var qty_lbl := Label.new()
		qty_lbl.text = "×%d" % count
		qty_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(qty_lbl)

		add_child(overlay)

	func _get_drag_data(_at: Vector2) -> Variant:
		if not _source_inv.has(_item_name):
			return null
		set_drag_preview(_gui_ref._make_drag_preview(_item_name, _count))
		return {"item": _item_name, "count": _count, "source_inv": _source_inv}


# ── Inventory drop slot ───────────────────────────────────────────────────────

class _InvDropSlot extends PanelContainer:
	var _gui_ref   # GUI node reference
	var _slot_index: int
	var _item_name: String = ""
	var _count: int = 0
	var _icon: TextureRect
	var _qty_lbl: Label

	func _init(gui_node, index: int) -> void:
		_gui_ref = gui_node
		_slot_index = index
		custom_minimum_size = Vector2(52, 52)

		var overlay := Control.new()
		overlay.custom_minimum_size = Vector2(52, 52)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_icon = TextureRect.new()
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(_icon)

		_qty_lbl = Label.new()
		_qty_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_qty_lbl.visible = false
		_qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(_qty_lbl)

		add_child(overlay)

	func set_item(item: String, count: int) -> void:
		_item_name = item
		_count = count
		tooltip_text = "%s ×%d" % [item, count]
		if _gui_ref != null:
			_icon.texture = _gui_ref._get_item_icon(item)
		_qty_lbl.text = "×%d" % count
		_qty_lbl.visible = true

	func clear_item() -> void:
		_item_name = ""
		_count = 0
		tooltip_text = ""
		_icon.texture = null
		_qty_lbl.visible = false

	func _get_drag_data(_at: Vector2) -> Variant:
		if _item_name == "" or _gui_ref == null:
			return null
		set_drag_preview(_gui_ref._make_drag_preview(_item_name, _count))
		return {"item": _item_name, "count": _count, "from_char_inv": true}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("item") and data.has("source_inv")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _gui_ref != null:
			_gui_ref.on_item_dropped_to_inv(data["item"], data["count"], data["source_inv"])


# ── Unit-to-unit inventory slot (drag between units in units panel) ────────────

class _UnitInvSlot extends PanelContainer:
	var _gui_ref
	var _unit
	var _item_name: String = ""
	var _count: int = 0
	var _icon: TextureRect
	var _qty_lbl: Label

	func _init(gui_node, unit_node) -> void:
		_gui_ref = gui_node
		_unit = unit_node
		custom_minimum_size = Vector2(40, 40)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.2)
		add_theme_stylebox_override("panel", style)

		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_icon = TextureRect.new()
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(_icon)

		_qty_lbl = Label.new()
		_qty_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_qty_lbl.visible = false
		_qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(_qty_lbl)

		add_child(overlay)

	func set_item(item: String, count: int) -> void:
		_item_name = item
		_count = count
		tooltip_text = "%s ×%d" % [item, count]
		if _gui_ref != null:
			_icon.texture = _gui_ref._get_item_icon(item)
		_qty_lbl.text = "×%d" % count
		_qty_lbl.visible = true

	func _get_drag_data(_at: Vector2) -> Variant:
		if _item_name == "":
			return null
		set_drag_preview(_gui_ref._make_drag_preview(_item_name, _count))
		return {"item": _item_name, "count": _count, "from_unit": _unit}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("from_unit") and data["from_unit"] != _unit

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var item: String = data["item"]
		var count: int = data["count"]
		var from_unit = data["from_unit"]
		from_unit.data.inventory[item] -= count
		if from_unit.data.inventory[item] <= 0:
			from_unit.data.inventory.erase(item)
		_unit.data.inventory[item] = _unit.data.inventory.get(item, 0) + count
		if _gui_ref != null:
			_gui_ref._refresh_units_panel()


# ── Minimap ───────────────────────────────────────────────────────────────────

class _MinimapControl extends Control:
	var _grid_ref
	var _camera_ref
	var _units_ref: Array
	var _main_node
	var _terrain_colors: Dictionary = {}
	var _map_img: Image
	var _map_tex: ImageTexture

	func _init(g, c, units: Array) -> void:
		_grid_ref = g
		_camera_ref = c
		_units_ref = units
		mouse_filter = MOUSE_FILTER_STOP

	func _ready() -> void:
		_main_node = get_tree().root.get_node("Main")
		_precompute_terrain()
		_map_img = Image.create(_grid_ref.width, _grid_ref.height, false, Image.FORMAT_RGBA8)
		_map_tex = ImageTexture.create_from_image(_map_img)

	func _precompute_terrain() -> void:
		for pos in _grid_ref.grid:
			var cell = _grid_ref.grid[pos]
			var col: Color
			if _grid_ref.water_tiles.has(pos):
				col = Color(0.15, 0.38, 0.72)
			elif _grid_ref.dirt_tiles.has(pos):
				col = Color(0.42, 0.29, 0.16)
			elif not cell.navigable:
				col = Color(0.38, 0.38, 0.40)
			else:
				col = Color(0.18, 0.36, 0.18)
			_terrain_colors[pos] = col

	func _get_tooltip(at_position: Vector2) -> String:
		var mm := size
		var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
		var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)
		# Units take priority — closest hovered unit wins. Downed teammates
		# stay in the hit-test so the player can hover the pulsing red dot
		# and see who needs rescuing.
		for u in _units_ref:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.evacuated:
				continue
			if unit_node.is_dead() and not unit_node.is_downed:
				continue
			var ux: float = (unit_node.position.x / world_w) * mm.x
			var uy: float = (unit_node.position.y / world_h) * mm.y
			if at_position.distance_to(Vector2(ux, uy)) <= 7.0:
				var tag: String = unit_node.data.role if unit_node.data.role != "" else "Survivor"
				if unit_node.is_downed:
					return "%s (%s) — DOWNED" % [unit_node.data.name, tag]
				return "%s (%s)" % [unit_node.data.name, tag]
		# Supply crates / drop pods next.
		for crate_pos in _grid_ref.crate_inventories.keys():
			var inv: Dictionary = _grid_ref.crate_inventories[crate_pos]
			if inv.is_empty():
				continue
			var cw: Vector2 = _grid_ref.gridToWorld(crate_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
			var cx: float = (cw.x / world_w) * mm.x
			var cy: float = (cw.y / world_h) * mm.y
			if at_position.distance_to(Vector2(cx, cy)) <= 8.0:
				return "Supply Crate / Drop Pod"
		# Crash site.
		var ship_pos: Vector2 = _grid_ref.crash_site_pos
		if ship_pos != Vector2(-1, -1):
			var ship_world: Vector2 = _grid_ref.gridToWorld(ship_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 2.0
			var sx: float = (ship_world.x / world_w) * mm.x
			var sy: float = (ship_world.y / world_h) * mm.y
			if at_position.distance_to(Vector2(sx, sy)) <= 8.0:
				return "Crashed Ship"
		# Evac shuttle (only present during EVAC state).
		if _main_node != null and _main_node.wave_manager != null:
			var evac_pos: Vector2 = _main_node.wave_manager.evac_pos
			if evac_pos != Vector2(-1, -1):
				var evac_world: Vector2 = _grid_ref.gridToWorld(evac_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
				var ex: float = (evac_world.x / world_w) * mm.x
				var ey: float = (evac_world.y / world_h) * mm.y
				if at_position.distance_to(Vector2(ex, ey)) <= 10.0:
					return "Rescue Shuttle"
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mm := size
			var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
			var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)
			var world_pos := Vector2(
				(event.position.x / mm.x) * world_w,
				(event.position.y / mm.y) * world_h
			)
			_camera_ref.center_on(world_pos)
			accept_event()

	func _process(_delta: float) -> void:
		_rebuild_map()
		queue_redraw()

	func _rebuild_map() -> void:
		if _main_node == null or _map_img == null:
			return
		var explored_img: Image = _main_node._explored_img
		var visible_cells: Dictionary = _main_node._visible_cells
		if explored_img == null:
			return
		var w: int = _grid_ref.width
		var h: int = _grid_ref.height
		for pos in _grid_ref.grid:
			var px: int = int(pos.x)
			var py: int = int(pos.y)
			if px < 0 or py < 0 or px >= w or py >= h:
				continue
			var lit: bool = visible_cells.has(Vector2i(px, py))
			var explored: bool = explored_img.get_pixel(px, py).r > 0.5
			var base: Color = _terrain_colors.get(pos, Color(0.1, 0.1, 0.1))
			var col: Color
			if lit:
				col = base
			elif explored:
				col = base.darkened(0.55)
			else:
				col = Color(0.04, 0.04, 0.06)
			_map_img.set_pixel(px, py, col)
		_map_tex.update(_map_img)

	func _draw() -> void:
		var mm := size
		draw_rect(Rect2(Vector2.ZERO, mm), Color(0.04, 0.04, 0.06))
		if _map_tex:
			draw_texture_rect(_map_tex, Rect2(Vector2.ZERO, mm), false)

		var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
		var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)

		# Crash site landmark (red square)
		var ship_pos: Vector2 = _grid_ref.crash_site_pos
		if ship_pos != Vector2(-1, -1):
			var ship_world: Vector2 = _grid_ref.gridToWorld(ship_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 2.0
			var sx: float = (ship_world.x / world_w) * mm.x
			var sy: float = (ship_world.y / world_h) * mm.y
			draw_rect(Rect2(sx - 4, sy - 4, 8, 8), Color(0.9, 0.15, 0.15, 0.9))
			draw_rect(Rect2(sx - 4, sy - 4, 8, 8), Color(1.0, 0.5, 0.5, 1.0), false, 1.0)

		# Supply crates / drop pods — gold pulsing dots so the player can
		# spot a fresh drop the moment the event banner announces one.
		# Looted-empty crates are skipped so the beacon turns off once a
		# unit has cleaned the crate out.
		var pulse_now: float = sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
		for crate_pos in _grid_ref.crate_inventories.keys():
			var inv: Dictionary = _grid_ref.crate_inventories[crate_pos]
			if inv.is_empty():
				continue
			var cw: Vector2 = _grid_ref.gridToWorld(crate_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
			var cx: float = (cw.x / world_w) * mm.x
			var cy: float = (cw.y / world_h) * mm.y
			# Halo + dot. Gold reads as "loot here" against the green/red
			# unit/ship markers without competing for attention.
			draw_circle(Vector2(cx, cy), 5.5 + pulse_now * 2.5, Color(1.0, 0.85, 0.30, 0.20))
			draw_circle(Vector2(cx, cy), 3.0, Color(1.0, 0.85, 0.30, 1.0))
			draw_arc(Vector2(cx, cy), 3.0, 0.0, TAU, 16, Color(0.4, 0.30, 0.05, 1.0), 0.75, true)

		# Evac shuttle landmark — pulsing green circle. Only present during the
		# EVAC state (WaveManager.evac_pos defaults to (-1, -1) outside it).
		if _main_node != null and _main_node.wave_manager != null:
			var evac_pos: Vector2 = _main_node.wave_manager.evac_pos
			if evac_pos != Vector2(-1, -1):
				var evac_world: Vector2 = _grid_ref.gridToWorld(evac_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
				var ex: float = (evac_world.x / world_w) * mm.x
				var ey: float = (evac_world.y / world_h) * mm.y
				var pulse: float = sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5  # 0..1
				# Outer halo, larger when pulsing — draws the eye to it.
				draw_circle(Vector2(ex, ey), 7.0 + pulse * 4.0, Color(0.25, 1.0, 0.45, 0.25))
				draw_circle(Vector2(ex, ey), 4.5, Color(0.25, 1.0, 0.45, 1.0))
				# Tiny outline for crisp readability over light terrain.
				draw_arc(Vector2(ex, ey), 4.5, 0.0, TAU, 24, Color(0.0, 0.4, 0.15, 1.0), 1.0, true)

		# Unit glows + dots. Simple two-state coloring so the player reads
		# health at a glance: green = alive (and able to walk to evac),
		# pulsing red = downed (needs rescue). Permanently-dead and
		# evacuated units are filtered out.
		for u in _units_ref:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.evacuated:
				continue
			if unit_node.is_dead() and not unit_node.is_downed:
				continue
			var wp: Vector2 = unit_node.position
			var mx: float = (wp.x / world_w) * mm.x
			var my: float = (wp.y / world_h) * mm.y
			if unit_node.is_downed:
				# Pulsing red so a fallen teammate is unmissable.
				var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.005) * 0.4
				draw_circle(Vector2(mx, my), 9.0, Color(1.0, 0.2, 0.2, 0.20 * pulse))
				draw_circle(Vector2(mx, my), 4.5, Color(1.0, 0.30, 0.30, 1.0))
			else:
				# Steady green for alive teammates.
				var alive_col: Color = Color(0.30, 0.95, 0.45)
				draw_circle(Vector2(mx, my), 9.0, Color(alive_col.r, alive_col.g, alive_col.b, 0.18))
				draw_circle(Vector2(mx, my), 5.5, Color(alive_col.r, alive_col.g, alive_col.b, 0.45))
				draw_circle(Vector2(mx, my), 3.5, alive_col)
				draw_arc(Vector2(mx, my), 3.5, 0.0, TAU, 16, Color(0, 0, 0, 0.85), 1.0, true)

		# Viewport rectangle — clipped to minimap bounds
		var vp_size: Vector2 = _camera_ref.get_viewport().get_visible_rect().size / _camera_ref.zoom
		var cam_tl: Vector2  = _camera_ref.global_position - vp_size * 0.5
		var rx: float = (cam_tl.x / world_w) * mm.x
		var ry: float = (cam_tl.y / world_h) * mm.y
		var rw: float = (vp_size.x  / world_w) * mm.x
		var rh: float = (vp_size.y  / world_h) * mm.y
		var vp_rect := Rect2(rx, ry, rw, rh)
		var mm_rect := Rect2(Vector2.ZERO, mm)
		var clipped := mm_rect.intersection(vp_rect)
		if clipped.size.x > 0 and clipped.size.y > 0:
			draw_rect(clipped, Color(1, 1, 1, 0.75), false, 0.5)


# Fullscreen-ish map overlay opened from the minimap's Expand button.
# Re-uses the same terrain texture + marker logic as _MinimapControl, just
# scaled up to a centered 80%-screen panel. Click anywhere to recenter the
# camera + close; tooltips fire on every marker the player hovers.
class _MapPanelControl extends Control:
	var _grid_ref
	var _camera_ref
	var _units_ref: Array
	var _main_node
	# Subview that actually draws the map; centered inside this overlay so
	# the click-to-close-on-outside region is the dim border, not the map.
	var _viewport: Control
	var _dim: ColorRect
	var _hint_lbl: Label

	func _init(g, c, units: Array) -> void:
		_grid_ref = g
		_camera_ref = c
		_units_ref = units
		mouse_filter = MOUSE_FILTER_STOP

	func _ready() -> void:
		_main_node = get_tree().root.get_node("Main")
		# Dim background so the world recedes while the map's open.
		_dim = ColorRect.new()
		_dim.color = Color(0, 0, 0, 0.65)
		_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_dim)
		# Centered viewport — 80% width / height of the parent so it looks
		# like a "tab" sitting on top of the world rather than a fullscreen
		# takeover.
		_viewport = Control.new()
		_viewport.anchor_left = 0.5
		_viewport.anchor_right = 0.5
		_viewport.anchor_top = 0.5
		_viewport.anchor_bottom = 0.5
		_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
		_viewport.gui_input.connect(_on_viewport_input)
		add_child(_viewport)
		# Help text at the bottom of the overlay.
		_hint_lbl = Label.new()
		_hint_lbl.text = "Click on the map to recenter camera   ·   Click outside to close"
		_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_lbl.modulate = Color(0.85, 0.85, 0.92)
		_hint_lbl.anchor_left = 0.0
		_hint_lbl.anchor_right = 1.0
		_hint_lbl.anchor_top = 1.0
		_hint_lbl.anchor_bottom = 1.0
		_hint_lbl.offset_top = -32
		_hint_lbl.offset_bottom = -8
		add_child(_hint_lbl)

	func _process(_delta: float) -> void:
		if not visible:
			return
		# Re-fit the viewport to ~80% of the overlay's current size each
		# tick so window resizes don't desync the map's bounding box.
		_size_viewport()
		queue_redraw()

	func _size_viewport() -> void:
		var s: Vector2 = size
		# Square the map so terrain proportions stay correct (world is
		# typically wider than it is tall but the marker math handles that
		# via per-axis scaling).
		var dim: float = min(s.x, s.y) * 0.80
		_viewport.offset_left   = -dim * 0.5
		_viewport.offset_right  =  dim * 0.5
		_viewport.offset_top    = -dim * 0.5
		_viewport.offset_bottom =  dim * 0.5

	# Background click → close. Inside the viewport, gui_input handles it.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Click landed outside the centered viewport (the dim border) →
			# close the overlay. Inside-viewport clicks are routed through
			# _on_viewport_input.
			visible = false
			accept_event()

	func _on_viewport_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mm: Vector2 = _viewport.size
			var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
			var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)
			var world_pos := Vector2(
				(event.position.x / mm.x) * world_w,
				(event.position.y / mm.y) * world_h
			)
			_camera_ref.center_on(world_pos)
			visible = false
			_viewport.accept_event()
		elif event is InputEventMouseMotion:
			# Tooltip lookup uses the same hit-test as the minimap, so
			# hovering ship / evac / crates / units shows their label.
			var tip: String = _tooltip_for(event.position)
			_viewport.tooltip_text = tip

	func _tooltip_for(at_position: Vector2) -> String:
		var mm: Vector2 = _viewport.size
		var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
		var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)
		# Scale hit radius up since markers render bigger here.
		var radius: float = 14.0
		for u in _units_ref:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.evacuated:
				continue
			if unit_node.is_dead() and not unit_node.is_downed:
				continue
			var ux: float = (unit_node.position.x / world_w) * mm.x
			var uy: float = (unit_node.position.y / world_h) * mm.y
			if at_position.distance_to(Vector2(ux, uy)) <= radius:
				var tag: String = unit_node.data.role if unit_node.data.role != "" else "Survivor"
				if unit_node.is_downed:
					return "%s (%s) — DOWNED" % [unit_node.data.name, tag]
				return "%s (%s)" % [unit_node.data.name, tag]
		for crate_pos in _grid_ref.crate_inventories.keys():
			var inv: Dictionary = _grid_ref.crate_inventories[crate_pos]
			if inv.is_empty():
				continue
			var cw: Vector2 = _grid_ref.gridToWorld(crate_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
			var cx: float = (cw.x / world_w) * mm.x
			var cy: float = (cw.y / world_h) * mm.y
			if at_position.distance_to(Vector2(cx, cy)) <= radius:
				return "Supply Crate / Drop Pod"
		var ship_pos: Vector2 = _grid_ref.crash_site_pos
		if ship_pos != Vector2(-1, -1):
			var ship_world: Vector2 = _grid_ref.gridToWorld(ship_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 2.0
			var sx: float = (ship_world.x / world_w) * mm.x
			var sy: float = (ship_world.y / world_h) * mm.y
			if at_position.distance_to(Vector2(sx, sy)) <= radius:
				return "Crashed Ship"
		if _main_node != null and _main_node.wave_manager != null:
			var evac_pos: Vector2 = _main_node.wave_manager.evac_pos
			if evac_pos != Vector2(-1, -1):
				var evac_world: Vector2 = _grid_ref.gridToWorld(evac_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
				var ex: float = (evac_world.x / world_w) * mm.x
				var ey: float = (evac_world.y / world_h) * mm.y
				if at_position.distance_to(Vector2(ex, ey)) <= radius:
					return "Rescue Shuttle"
		return ""

	# All drawing happens via the viewport child so it's clipped to the
	# centered region. We piggyback on its draw via `draw` callback.
	func _draw() -> void:
		# Frame around the viewport so the map area reads as a window.
		var vp_rect: Rect2 = Rect2(_viewport.position, _viewport.size)
		draw_rect(vp_rect, Color(0.08, 0.08, 0.10, 1.0), true)
		draw_rect(vp_rect, Color(0.85, 0.85, 0.95, 0.6), false, 2.0)
		# Render markers + a fresh terrain image scaled to the viewport.
		_draw_map_into(vp_rect)

	# Draws the same content as the minimap into `rect` (overlay coords).
	func _draw_map_into(rect: Rect2) -> void:
		var world_w: float = _grid_ref.width  * float(_grid_ref.cell_size)
		var world_h: float = _grid_ref.height * float(_grid_ref.cell_size)
		var mm: Vector2 = rect.size
		var origin: Vector2 = rect.position
		# Pull the same _map_tex the minimap maintains so we don't duplicate
		# the per-frame terrain rebuild.
		var minimap = get_tree().root.get_node_or_null("Main/CanvasLayer/GUI")
		var src_tex: Texture2D = null
		if minimap != null and minimap._minimap is _MinimapControl:
			src_tex = (minimap._minimap as _MinimapControl)._map_tex
		if src_tex != null:
			draw_texture_rect(src_tex, rect, false)
		# Crash site (red square)
		var ship_pos: Vector2 = _grid_ref.crash_site_pos
		if ship_pos != Vector2(-1, -1):
			var ship_world: Vector2 = _grid_ref.gridToWorld(ship_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 2.0
			var sx: float = origin.x + (ship_world.x / world_w) * mm.x
			var sy: float = origin.y + (ship_world.y / world_h) * mm.y
			draw_rect(Rect2(sx - 8, sy - 8, 16, 16), Color(0.9, 0.15, 0.15, 0.9))
			draw_rect(Rect2(sx - 8, sy - 8, 16, 16), Color(1.0, 0.5, 0.5, 1.0), false, 2.0)
		# Supply crates
		var pulse_now: float = sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
		for crate_pos in _grid_ref.crate_inventories.keys():
			var inv: Dictionary = _grid_ref.crate_inventories[crate_pos]
			if inv.is_empty():
				continue
			var cw: Vector2 = _grid_ref.gridToWorld(crate_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
			var cx: float = origin.x + (cw.x / world_w) * mm.x
			var cy: float = origin.y + (cw.y / world_h) * mm.y
			draw_circle(Vector2(cx, cy), 11.0 + pulse_now * 4.0, Color(1.0, 0.85, 0.30, 0.20))
			draw_circle(Vector2(cx, cy), 6.0, Color(1.0, 0.85, 0.30, 1.0))
			draw_arc(Vector2(cx, cy), 6.0, 0.0, TAU, 20, Color(0.4, 0.30, 0.05, 1.0), 1.5, true)
		# Evac shuttle
		if _main_node != null and _main_node.wave_manager != null:
			var evac_pos: Vector2 = _main_node.wave_manager.evac_pos
			if evac_pos != Vector2(-1, -1):
				var evac_world: Vector2 = _grid_ref.gridToWorld(evac_pos) + Vector2(_grid_ref.cell_size, _grid_ref.cell_size) * 0.5
				var ex: float = origin.x + (evac_world.x / world_w) * mm.x
				var ey: float = origin.y + (evac_world.y / world_h) * mm.y
				var pulse: float = sin(Time.get_ticks_msec() * 0.005) * 0.5 + 0.5
				draw_circle(Vector2(ex, ey), 14.0 + pulse * 7.0, Color(0.25, 1.0, 0.45, 0.25))
				draw_circle(Vector2(ex, ey), 9.0, Color(0.25, 1.0, 0.45, 1.0))
				draw_arc(Vector2(ex, ey), 9.0, 0.0, TAU, 28, Color(0.0, 0.4, 0.15, 1.0), 1.5, true)
		# Units — green if alive, pulsing red if downed. Permanently-dead
		# and evacuated are filtered; downed stay visible so the player
		# can see fallen teammates and dispatch a rescuer.
		for u in _units_ref:
			if not is_instance_valid(u):
				continue
			var unit_node: Unit = u as Unit
			if unit_node.evacuated:
				continue
			if unit_node.is_dead() and not unit_node.is_downed:
				continue
			var wp: Vector2 = unit_node.position
			var ux: float = origin.x + (wp.x / world_w) * mm.x
			var uy: float = origin.y + (wp.y / world_h) * mm.y
			if unit_node.is_downed:
				var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.005) * 0.4
				draw_circle(Vector2(ux, uy), 18.0, Color(1.0, 0.2, 0.2, 0.20 * pulse))
				draw_circle(Vector2(ux, uy), 9.0, Color(1.0, 0.30, 0.30, 1.0))
			else:
				var alive_col: Color = Color(0.30, 0.95, 0.45)
				draw_circle(Vector2(ux, uy), 18.0, Color(alive_col.r, alive_col.g, alive_col.b, 0.18))
				draw_circle(Vector2(ux, uy), 11.0, Color(alive_col.r, alive_col.g, alive_col.b, 0.45))
				draw_circle(Vector2(ux, uy), 7.0, alive_col)
				draw_arc(Vector2(ux, uy), 7.0, 0.0, TAU, 24, Color(0, 0, 0, 0.85), 1.5, true)
		# Viewport rectangle
		var vp_size: Vector2 = _camera_ref.get_viewport().get_visible_rect().size / _camera_ref.zoom
		var cam_tl: Vector2  = _camera_ref.global_position - vp_size * 0.5
		var rx: float = origin.x + (cam_tl.x / world_w) * mm.x
		var ry: float = origin.y + (cam_tl.y / world_h) * mm.y
		var rw: float = (vp_size.x / world_w) * mm.x
		var rh: float = (vp_size.y / world_h) * mm.y
		draw_rect(Rect2(rx, ry, rw, rh), Color(1, 1, 1, 0.85), false, 1.5)


# ── Loot drop slot (source inventory — drag out AND accept drops back) ────────

class _LootDropSlot extends PanelContainer:
	var _gui_ref
	var _item_name: String = ""
	var _count: int = 0
	var _icon: TextureRect
	var _qty_lbl: Label

	func _init(gui_node) -> void:
		_gui_ref = gui_node
		custom_minimum_size = Vector2(52, 52)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.2)
		add_theme_stylebox_override("panel", style)

		var overlay := Control.new()
		overlay.mouse_filter = MOUSE_FILTER_IGNORE

		_icon = TextureRect.new()
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.mouse_filter = MOUSE_FILTER_IGNORE
		overlay.add_child(_icon)

		_qty_lbl = Label.new()
		_qty_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_qty_lbl.visible = false
		_qty_lbl.mouse_filter = MOUSE_FILTER_IGNORE
		overlay.add_child(_qty_lbl)
		add_child(overlay)

	func set_item(item: String, count: int) -> void:
		_item_name = item
		_count = count
		tooltip_text = "%s ×%d" % [item, count]
		if _gui_ref != null:
			_icon.texture = _gui_ref._get_item_icon(item)
		_qty_lbl.text = "×%d" % count
		_qty_lbl.visible = true

	func clear_item() -> void:
		_item_name = ""
		_count = 0
		tooltip_text = ""
		_icon.texture = null
		_qty_lbl.visible = false

	func _get_drag_data(_at: Vector2) -> Variant:
		if _item_name == "" or _gui_ref == null:
			return null
		set_drag_preview(_gui_ref._make_drag_preview(_item_name, _count))
		return {"item": _item_name, "count": _count, "source_inv": _gui_ref._loot_source_inv}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("item") and data.has("from_char_inv")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _gui_ref == null:
			return
		var item: String = data["item"]
		var count: int = data["count"]
		var unit: Unit = _gui_ref._char_inv_unit
		if unit == null:
			return
		unit.data.inventory[item] -= count
		if unit.data.inventory[item] <= 0:
			unit.data.inventory.erase(item)
		_gui_ref._loot_source_inv[item] = _gui_ref._loot_source_inv.get(item, 0) + count
		_gui_ref._refresh_loot_panel()
		_gui_ref._refresh_char_inv_panel()
