extends Control
## UI for the tn2019quest Godot port, indie-quest style.
##
## Layout: header (hero + restart) on top; below it the game row with
## the scene panel on the left and a sidebar on the right holding the
## dialog text, answer buttons, inventory/journal buttons and the D-pad.
## On narrow windows (phones, portrait) the sidebar moves under the
## scene instead. The scene tiles scale to fill the scene panel, so the
## sprites stay large on wide windows instead of sitting tiny in the
## middle of an empty panel.
## Dialog photos replace the whole scene: the photo is shown where the
## tile map was, and the dialog with answers stays in the sidebar
## exactly like any other dialog. No modal, no overlay, no dim.
##
## No emoji anywhere in the UI chrome: the web export has no system
## font fallback, so emoji render as tofu boxes there (desktop builds
## hide this via system fonts). Arrows are drawn procedurally as icon
## textures, doors and marks are coloured panels, everything else is
## plain text. Dialog and answer texts keep their emoji on desktop, but
## on Web they are stripped (words remain) for the same reason.
##
## Map tiles are drawn as panels (coloured by tile type) with a sprite
## inside. Sprite tiles animate: characters cycle 3 frames,
## fire cycles faster. Game logic lives in quest_engine.gd; progress is
## saved automatically after every answer (user://tn2019quest_save.json).
## Controls: click an answer, or arrows / WASD for movement answers
## (physical keys, so WASD also works on a Russian layout).

const QuestEngineScript := preload("res://scripts/quest_engine.gd")
var engine := QuestEngineScript.new()

var vbox: VBoxContainer
var game_row: HBoxContainer
var hero_label: Label
var reset_toshik_button: Button
var reset_nastya_button: Button
var scene_panel: PanelContainer
var scene_grid: GridContainer
var fog_overlay: Control
var fog_runs: Array = []
var sidebar: PanelContainer
var dialog_card: PanelContainer
var dialog_margin: MarginContainer
var dialog_frame_layer: Control
var hero_portrait: TextureRect
var dialog_label: RichTextLabel
var input_block: VBoxContainer
var input_row: HBoxContainer
var text_input: LineEdit
# Web-mobile native answer input (see _sync_native_answer_input):
# the game's LineEdit drops composed virtual-keyboard text on
# Android web, so hidden-answer dialogs use a real HTML <input>
# bridged back via JavaScriptBridge. The callback reference must
# be kept, or the engine's refcounting frees it.
var native_input_active := false
var native_answer_callback = null
var submit_button: Button
var feedback_label: Label
var answers_box: VBoxContainer
var dpad_block: VBoxContainer
var inv_row: HBoxContainer
var dpad_pad: GridContainer
var dpad_buttons := {}
var photo_rect: TextureRect
var showing_photo := false

var animated_tiles: Array = []
# Characters do not cycle frames: they squash (see _process).
var squash_sprites: Array = []
var small_sprites: Array = []
var card_sprites: Array = []
var scaled_sprites: Array = []
var anim_time := 0.0
var arrow_icons := {}
var scene_cols := 0
var scene_rows := 0
var layout_narrow := false
var layout_init_done := false
# Mobile dialog sheet: in narrow layout, a dialog with no movement
# arrows expands the sidebar into a full sheet covering the scene.
var dialog_expanded := false
var dialog_expand_tween: Tween
var dialog_expand_from_top := 0.0

const FALLBACK_CELL := 64
const MIN_CELL := 40
# Light scene palette (the user picked a light scene so the remaining
# white sprite fringe blends in instead of glowing on dark tiles).
# The floor is the scene panel's own background, not a tile at all.
const SCENE_BG := Color(0.91, 0.89, 0.83)
const ROAD_COLOR := Color(0.14, 0.14, 0.15)
const DOOR_COLOR := Color(0.42, 0.29, 0.17)
const BRICK_COLOR := Color(0.62, 0.36, 0.24)
# Wedding-invitation palette (user-approved restyle): deep plum-brown
# sidebar, ivory parchment cards, gold trim, dark-brown card text.
const GOLD := Color(0.78, 0.62, 0.28)
const SIDEBAR_BG := Color(0.24, 0.17, 0.19)
const PARCHMENT := Color(0.96, 0.93, 0.84)
const PARCHMENT_TEXT := Color(0.25, 0.18, 0.12)
const BUTTON_BG := Color(0.42, 0.30, 0.20)
const BUTTON_HOVER := Color(0.52, 0.38, 0.26)
const BUTTON_PRESSED := Color(0.32, 0.22, 0.15)
const IVORY := Color(0.96, 0.93, 0.84)
const NARROW_WIDTH := 760
const SIDEBAR_WIDTH := 380
const MOVE_CODES := ["t", "d", "l", "r", "i", "j"]
const MOVE_WORDS := {
	"t": "Вверх", "d": "Вниз", "l": "Влево", "r": "Вправо",
	"i": "Инвентарь", "j": "Журнал",
}
const MOVE_KEYS := {
	KEY_UP: "t", KEY_W: "t",
	KEY_DOWN: "d", KEY_S: "d",
	KEY_LEFT: "l", KEY_A: "l",
	KEY_RIGHT: "r", KEY_D: "r",
}
# Pickup items render at half cell size; fire stays full; characters
# render at CHAR_SPRITE_SCALE (see SPRITE_SCALE) so their heads clear
# the cell edge.
const ITEM_SPRITES := ["monocle", "extinguisher", "boots", "key", "shoe"]
# Items drawn as a note/photo card lying on the floor: the sprite
# itself is untouched, it is composited at runtime onto a procedural
# ivory card (slightly rotated, soft shadow). Only "shoe" for now.
const CARD_ITEM_SPRITES := ["shoe"]
# Big static items: a phone booth is furniture, not a pocket item —
# it gets character height but never squashes like a character.
const BIG_ITEM_SPRITES := {"taxofon": 0.9}
# Per-sprite display scale in a scene cell (1.0 = full cell). Zags
# fills her canvas edge to edge, so she reads a third taller than the
# other characters; 0.8 brings her in line with them. Every other
# character defaults to 0.9: measured, all AI frames fill their canvas
# edge to edge (top=0, bottom=512), so at full cell height the heads
# sit exactly on the cell border and read as cut off, and the 12 px
# frame difference hops the figure; a 0.9 scale leaves a 5% margin
# that absorbs the hop.
const SPRITE_SCALE := {"zags": 0.8, "kolyan": 0.7}
const CHAR_SPRITE_SCALE := 0.9
# Map character -> sprite set in assets/sprites/ (<name>_0.png, _1, _2).
const SPRITES := {
	"O": "toshik", "N": "nastya", "Z": "zags", "J": "jacob",
	"k": "kolyan", "U": "kolyan", "K": "sedosh", "S": "sokrat",
	"B": "bartender", "P": "policeman", "c": "crowd", "C": "crowd",
	"T": "crowd", "G": "genich", "R": "repa", "o": "okusheva",
	# ZAGS guests (digits reuse existing sets; the engine maps them
	# through the emoji fallback, so no new art is needed): 1-7 the
	# congratulating guests, 8 Jacob/Yakov (typo line), 9 Tolik
	# (sokrat's set), 0 the registry worker (generic crowd set).
	"1": "repa", "2": "zags", "3": "kolyan", "4": "genich",
	"5": "bartender", "6": "policeman", "7": "sedosh", "8": "jacob",
	"9": "sokrat", "0": "crowd",
	"F": "fire", "M": "monocle", "f": "extinguisher", "b": "boots",
	"?": "key", "v": "shoe", "z": "taxofon",
}
func _ready() -> void:
	engine.load_data("res://data/quest.json")
	_build_ui()
	_setup_native_answer_callback()
	if engine.has_save() and engine.load_save():
		pass
	else:
		engine.new_game()
		engine.save()
	_refresh()


func _process(delta: float) -> void:
	anim_time += delta
	for tile in animated_tiles:
		tile["elapsed"] += delta
		if tile["elapsed"] >= tile["interval"]:
			tile["elapsed"] = 0.0
			tile["idx"] = (tile["idx"] + 1) % tile["frames"].size()
			tile["node"].texture = tile["frames"][tile["idx"]]
	# Characters breathe instead of hopping: a gentle vertical squash
	# (head dips down, feet planted via the bottom-center pivot), so
	# the head never rises toward the cell edge the way the 12 px
	# frame difference used to push it.
	for entry in squash_sprites:
		entry["phase"] += delta
		var sy: float = 1.0 - 0.05 * (0.5 + 0.5 * sin(entry["phase"] * 4.0))
		entry["node"].scale = Vector2(1.0, sy)


# --- UI construction --------------------------------------------------------

func _panel_style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border.a > 0:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = border
	return style


func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = GOLD
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


func _style_button(button: Button) -> void:
	# One wood-and-gold button style for every button in the game:
	# answers, inventory/journal, D-pad, reset, submit.
	button.add_theme_stylebox_override("normal", _button_style(BUTTON_BG))
	button.add_theme_stylebox_override("hover", _button_style(BUTTON_HOVER))
	button.add_theme_stylebox_override("pressed", _button_style(BUTTON_PRESSED))
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", IVORY)
	button.add_theme_color_override("font_pressed_color", IVORY)
	button.add_theme_color_override("font_disabled_color", Color(IVORY.r, IVORY.g, IVORY.b, 0.5))
	# Tappable targets: every button is at least _button_min_height()
	# tall (64 on narrow windows, 56 on desktops), so answer buttons
	# (and the D-pad arrows) are comfortable to press on a phone.
	var ms := button.custom_minimum_size
	ms.y = max(ms.y, _button_min_height())
	button.custom_minimum_size = ms


func _is_narrow_window() -> bool:
	# The single narrow check for layout AND tap targets. Phones
	# report the viewport in device pixels, so a portrait phone is
	# 1080+ px wide and never trips the width threshold alone;
	# portrait aspect catches it regardless of pixel density.
	# Button sizes must use this, not the width alone, or a
	# portrait phone gets the stacked layout with desktop-sized
	# buttons (the 2026-10-31 bug: 56 px buttons on a phone).
	var vp := get_viewport_rect().size
	return vp.x < NARROW_WIDTH or vp.y > vp.x


func _button_min_height() -> int:
	# Narrow layout (phones in portrait) gets taller tap targets;
	# desktops keep the 56 px standard.
	if _is_narrow_window():
		return 64
	return 56


func _dialog_button_min_height() -> int:
	# Dialog-area buttons (answers, inventory/journal, submit) are
	# much taller than the header buttons in narrow layout, where
	# the user reads them as the main controls: 112 px is exactly
	# double the old 56 (and matches the arrow pads), and with the
	# expanded dialog sheet every answer list fits without scrolling.
	# Desktops keep 56.
	if _is_narrow_window():
		return 112
	return 56


func _dpad_button_size() -> int:
	# Arrow buttons are square; much bigger in narrow layout (their
	# icons scale via expand_icon): 112 px is close to double the
	# old 64, and a 3x112 pad still fits a narrow scene panel.
	# Wide keeps 52 wide; the height there stays the 56 floor
	# from _button_min_height().
	if _is_narrow_window():
		return 112
	return 52


func _set_button_height(button: Button, h: int) -> void:
	if button == null:
		return
	var ms := button.custom_minimum_size
	ms.y = h
	button.custom_minimum_size = ms


func _pad_button_sides(button: Button, pad: int) -> void:
	# StyleBoxFlat content margins are per state; bump all three so
	# the text stops hugging the gold border.
	for state in ["normal", "hover", "pressed"]:
		var sb := button.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = pad
			sb.content_margin_right = pad


func _try_font(path: String) -> FontFile:
	# Serif fonts activate automatically once the TTFs are in
	# res://assets/fonts/; until then the default font is used, so a
	# build without the (binary, user-pushed) font files still works.
	if ResourceLoader.exists(path):
		return load(path) as FontFile
	return null


func _parchment_image() -> Image:
	# 256x256 ivory parchment with a double gold border and small gold
	# corner flourishes. The dialog frame is NOT a 9-slice stylebox:
	# the corners are cropped out of this image as fixed 48 px sprites
	# and the border lines are separate rects (see _build_dialog_frame),
	# so only the lines ever stretch with the card.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(PARCHMENT)
	for x in range(256):
		for k in range(5):
			img.set_pixel(x, k, GOLD)
			img.set_pixel(x, 255 - k, GOLD)
	for y in range(256):
		for k in range(5):
			img.set_pixel(k, y, GOLD)
			img.set_pixel(255 - k, y, GOLD)
	for x in range(16, 240):
		for k in range(2):
			img.set_pixel(x, 16 + k, GOLD)
			img.set_pixel(x, 239 - k, GOLD)
	for y in range(16, 240):
		for k in range(2):
			img.set_pixel(16 + k, y, GOLD)
			img.set_pixel(239 - k, y, GOLD)
	# Corner flourishes: two intersecting rings (wedding rings for the
	# invitation theme), anti-aliased so the small circles read as
	# smooth rings rather than polygons. Both rings stay inside the
	# 48 px corner, clear of the inner border line.
	var corners: Array = [[28, 28, 1, 1], [227, 28, -1, 1], [28, 227, 1, -1], [227, 227, -1, -1]]
	for c in corners:
		var cx: int = c[0]
		var cy: int = c[1]
		var sx: int = c[2]
		var sy: int = c[3]
		for ring in [Vector2i(cx, cy), Vector2i(cx + sx * 9, cy + sy * 9)]:
			for dx in range(-11, 12):
				for dy in range(-11, 12):
					var dist: float = sqrt(float(dx * dx + dy * dy))
					var dd: float = abs(dist - 9.0)
					if dd < 1.5:
						var a: float = clamp(1.5 - dd, 0.0, 1.0)
						var bg: Color = img.get_pixel(ring.x + dx, ring.y + dy)
						img.set_pixel(ring.x + dx, ring.y + dy, GOLD * a + bg * (1.0 - a))
	return img


func _build_dialog_frame(card: PanelContainer) -> void:
	# The frame is built from pieces, not a 9-slice: four fixed 48 px
	# corner sprites (borders + rings baked in, never scaled) and
	# eight solid gold line rects that stretch only along their own
	# side — top/bottom lines stretch horizontally, left/right lines
	# vertically. Corners can no longer distort or lose the top edge
	# however wide or tall the dialog card grows.
	var img := _parchment_image()
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(PRESET_FULL_RECT)
	card.add_child(layer)
	dialog_frame_layer = layer
	var corner_defs: Array = [
		[Vector2i(0, 0), Vector2(0, 0), Vector2i(0, 0)],
		[Vector2i(208, 0), Vector2(1, 0), Vector2i(-48, 0)],
		[Vector2i(0, 208), Vector2(0, 1), Vector2i(0, -48)],
		[Vector2i(208, 208), Vector2(1, 1), Vector2i(-48, -48)],
	]
	for def in corner_defs:
		var src: Vector2i = def[0]
		var anch: Vector2 = def[1]
		var off: Vector2i = def[2]
		var cimg := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		cimg.blit_rect(img, Rect2i(src, Vector2i(48, 48)), Vector2i.ZERO)
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(cimg)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = MOUSE_FILTER_IGNORE
		rect.anchor_left = anch.x
		rect.anchor_top = anch.y
		rect.anchor_right = anch.x
		rect.anchor_bottom = anch.y
		rect.offset_left = off.x
		rect.offset_top = off.y
		rect.offset_right = off.x + 48
		rect.offset_bottom = off.y + 48
		layer.add_child(rect)
	# [anchor_left, anchor_top, anchor_right, anchor_bottom,
	#  offset_left, offset_top, offset_right, offset_bottom]
	var lines: Array = [
		[0.0, 0.0, 1.0, 0.0, 48, 0, -48, 5],
		[0.0, 1.0, 1.0, 1.0, 48, -5, -48, 0],
		[0.0, 0.0, 0.0, 1.0, 0, 48, 5, -48],
		[1.0, 0.0, 1.0, 1.0, -5, 48, 0, -48],
		[0.0, 0.0, 1.0, 0.0, 48, 16, -48, 18],
		[0.0, 1.0, 1.0, 1.0, 48, -18, -48, -16],
		[0.0, 0.0, 0.0, 1.0, 16, 48, 18, -48],
		[1.0, 0.0, 1.0, 1.0, -18, 48, -16, -48],
	]
	for ln in lines:
		var r := ColorRect.new()
		r.color = GOLD
		r.mouse_filter = MOUSE_FILTER_IGNORE
		r.anchor_left = ln[0]
		r.anchor_top = ln[1]
		r.anchor_right = ln[2]
		r.anchor_bottom = ln[3]
		r.offset_left = ln[4]
		r.offset_top = ln[5]
		r.offset_right = ln[6]
		r.offset_bottom = ln[7]
		layer.add_child(r)


func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	var portrait_frame := PanelContainer.new()
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0), GOLD, 8))
	hero_portrait = TextureRect.new()
	hero_portrait.custom_minimum_size = Vector2(48, 48)
	hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(hero_portrait)
	header.add_child(portrait_frame)
	hero_label = Label.new()
	hero_label.size_flags_horizontal = SIZE_EXPAND_FILL
	hero_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hero_label.add_theme_font_size_override("font_size", 24)
	hero_label.add_theme_color_override("font_color", GOLD)
	header.add_child(hero_label)
	reset_toshik_button = Button.new()
	reset_toshik_button.text = "Заново за Тошика"
	reset_toshik_button.focus_mode = FOCUS_NONE
	reset_toshik_button.add_theme_font_size_override("font_size", 20)
	_style_button(reset_toshik_button)
	_pad_button_sides(reset_toshik_button, 18)
	reset_toshik_button.pressed.connect(_on_reset_toshik)
	header.add_child(reset_toshik_button)
	reset_nastya_button = Button.new()
	reset_nastya_button.text = "Заново за Настю"
	reset_nastya_button.focus_mode = FOCUS_NONE
	reset_nastya_button.add_theme_font_size_override("font_size", 20)
	_style_button(reset_nastya_button)
	_pad_button_sides(reset_nastya_button, 18)
	reset_nastya_button.pressed.connect(_on_reset_nastya)
	header.add_child(reset_nastya_button)
	vbox.add_child(header)
	var header_divider := Panel.new()
	header_divider.custom_minimum_size = Vector2(0, 2)
	header_divider.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0, 0, 0, 0), 0))
	vbox.add_child(header_divider)

	# Game row: scene on the left, sidebar on the right (wide windows).
	game_row = HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 12)
	game_row.size_flags_vertical = SIZE_EXPAND_FILL
	game_row.size_flags_stretch_ratio = 1.2
	vbox.add_child(game_row)

	# Scene panel.
	scene_panel = PanelContainer.new()
	scene_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	scene_panel.size_flags_vertical = SIZE_EXPAND_FILL
	scene_panel.add_theme_stylebox_override("panel", _panel_style(SCENE_BG, GOLD))
	game_row.add_child(scene_panel)
	var scene_center := CenterContainer.new()
	scene_panel.add_child(scene_center)
	scene_grid = GridContainer.new()
	# No gaps: walls and roads merge into continuous shapes; the floor
	# is the scene panel's own background, not a tile at all.
	scene_grid.add_theme_constant_override("h_separation", 0)
	scene_grid.add_theme_constant_override("v_separation", 0)
	scene_center.add_child(scene_grid)
	# Fog overlay: a plain Control (not a container, so its children
	# keep free positions), centred over the grid by the CenterContainer.
	# Its fog-run children swallow the corridor downward to the panel's
	# bottom edge, so the dark corridor has no visible end.
	fog_overlay = Control.new()
	fog_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	fog_overlay.visible = false
	scene_center.add_child(fog_overlay)
	# Photo view: one persistent TextureRect, shown instead of the tile
	# map for photo dialogs. Centred like the grid, sized just inside
	# the gold scene frame (see _refresh and _apply_cell_size).
	photo_rect = TextureRect.new()
	photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo_rect.visible = false
	scene_center.add_child(photo_rect)
	# D-pad overlay: a plain Control stacked over the scene — the
	# PanelContainer fits every child to its full rect, so this layer
	# covers the scene and the arrow pad can anchor to its
	# bottom-right corner. Clicks pass through it except on buttons.
	var scene_overlay := Control.new()
	scene_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	scene_panel.add_child(scene_overlay)

	# Sidebar: dialog, answers,
	# inventory/journal buttons, D-pad, hint — all scrollable.
	sidebar = PanelContainer.new()
	sidebar.add_theme_stylebox_override("panel", _panel_style(SIDEBAR_BG, GOLD))
	sidebar.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
	sidebar.size_flags_vertical = SIZE_EXPAND_FILL
	game_row.add_child(sidebar)
	var sidebar_margin := MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 14)
	sidebar_margin.add_theme_constant_override("margin_right", 14)
	sidebar_margin.add_theme_constant_override("margin_top", 12)
	sidebar_margin.add_theme_constant_override("margin_bottom", 12)
	sidebar.add_child(sidebar_margin)
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_margin.add_child(sidebar_scroll)
	var sidebar_box := VBoxContainer.new()
	sidebar_box.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_box.add_theme_constant_override("separation", 12)
	sidebar_scroll.add_child(sidebar_box)

	# Dialog as a wedding-invitation card: ivory parchment, double gold
	# border, corner flourishes (baked into a 9-slice texture).
	dialog_card = PanelContainer.new()
	dialog_card.add_theme_stylebox_override("panel", _panel_style(PARCHMENT, Color(0, 0, 0, 0), 0))
	dialog_card.size_flags_horizontal = SIZE_EXPAND_FILL
	# The frame corners are fixed 48 px sprites top + bottom, so the
	# card needs at least 96 px of height for them not to overlap; a
	# one-line dialog is only ~63 px tall, so without a floor the
	# corners would collide. 120 px leaves a small center strip.
	dialog_card.custom_minimum_size = Vector2(0, 120)
	sidebar_box.add_child(dialog_card)
	_build_dialog_frame(dialog_card)
	dialog_margin = MarginContainer.new()
	# The flat parchment background carries no content margins (the
	# old 9-slice contributed 20 px), so the margin alone must inset
	# the text: 36/34 px restores the old text position and clears
	# the frame's inner line (16-18 px) with room to spare.
	dialog_margin.add_theme_constant_override("margin_left", 56)
	dialog_margin.add_theme_constant_override("margin_right", 56)
	dialog_margin.add_theme_constant_override("margin_top", 34)
	dialog_margin.add_theme_constant_override("margin_bottom", 34)
	dialog_card.add_child(dialog_margin)
	dialog_label = RichTextLabel.new()
	dialog_label.bbcode_enabled = true
	# Explicit wrap: without it a long dialog line would widen the
	# sidebar (and shrink the scene) instead of wrapping in place.
	dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_fit_content(dialog_label)
	# RichTextLabel keeps a separate size per run style: overriding
	# only normal_font_size left bold/italic runs at the default 16,
	# which is why marked-up words rendered oddly small on Web.
	dialog_label.add_theme_font_size_override("normal_font_size", 22)
	dialog_label.add_theme_font_size_override("bold_font_size", 22)
	dialog_label.add_theme_font_size_override("italics_font_size", 22)
	dialog_label.add_theme_font_size_override("bold_italics_font_size", 22)
	dialog_label.add_theme_color_override("default_color", PARCHMENT_TEXT)
	dialog_label.size_flags_horizontal = SIZE_EXPAND_FILL
	dialog_margin.add_child(dialog_label)
	var dialog_divider := Panel.new()
	dialog_divider.custom_minimum_size = Vector2(0, 3)
	dialog_divider.add_theme_stylebox_override("panel", _panel_style(GOLD, Color(0, 0, 0, 0), 0))
	sidebar_box.add_child(dialog_divider)

	# Free-text input, shown only when the current dialog has hidden
	# answers (the Demianov phone-call riddles): in the Telegram
	# original the player typed these, there was no button for them.
	input_block = VBoxContainer.new()
	input_block.add_theme_constant_override("separation", 6)
	input_block.size_flags_horizontal = SIZE_EXPAND_FILL
	input_block.visible = false
	sidebar_box.add_child(input_block)
	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	input_block.add_child(input_row)
	text_input = LineEdit.new()
	text_input.placeholder_text = "Введите ответ…"
	text_input.size_flags_horizontal = SIZE_EXPAND_FILL
	text_input.add_theme_font_size_override("font_size", 20)
	text_input.text_submitted.connect(_on_text_submit)
	input_row.add_child(text_input)
	submit_button = Button.new()
	submit_button.text = "Ответить"
	submit_button.focus_mode = FOCUS_NONE
	submit_button.add_theme_font_size_override("font_size", 20)
	_style_button(submit_button)
	_set_button_height(submit_button, _dialog_button_min_height())
	submit_button.pressed.connect(_on_text_submit)
	input_row.add_child(submit_button)
	feedback_label = Label.new()
	feedback_label.add_theme_font_size_override("font_size", 16)
	feedback_label.add_theme_color_override("font_color", IVORY)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.size_flags_horizontal = SIZE_EXPAND_FILL
	input_block.add_child(feedback_label)

	answers_box = VBoxContainer.new()
	answers_box.add_theme_constant_override("separation", 8)
	answers_box.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_box.add_child(answers_box)

	# Inventory/journal buttons. The arrow pad itself is overlaid on
	# the scene's bottom-right corner (see scene_overlay above), so
	# the sidebar keeps its space for dialog text and answers.
	dpad_block = VBoxContainer.new()
	dpad_block.add_theme_constant_override("separation", 8)
	dpad_block.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_box.add_child(dpad_block)
	inv_row = HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 8)
	dpad_block.add_child(inv_row)
	for code in ["i", "j"]:
		var button := Button.new()
		button.text = MOVE_WORDS[code]
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.focus_mode = FOCUS_NONE
		button.add_theme_font_size_override("font_size", 18)
		_style_button(button)
		_set_button_height(button, _dialog_button_min_height())
		button.pressed.connect(_on_move.bind(code))
		inv_row.add_child(button)
		dpad_buttons[code] = button
	dpad_pad = GridContainer.new()
	dpad_pad.columns = 3
	dpad_pad.add_theme_constant_override("h_separation", 4)
	dpad_pad.add_theme_constant_override("v_separation", 4)
	scene_overlay.add_child(dpad_pad)
	var dpad := dpad_pad
	# Row 1: (empty) / up / (empty); row 2: left / centre / right;
	# row 3: (empty) / down / (empty).
	var dpad_layout := ["", "t", "", "l", "", "r", "", "d", ""]
	var ds := _dpad_button_size()
	for code in dpad_layout:
		if code == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(ds, ds)
			dpad.add_child(spacer)
		else:
			var button := Button.new()
			button.icon = _arrow_icon(code)
			button.expand_icon = true
			button.custom_minimum_size = Vector2(ds, ds)
			button.focus_mode = FOCUS_NONE
			_style_button(button)
			button.pressed.connect(_on_move.bind(code))
			dpad.add_child(button)
			dpad_buttons[code] = button



	# Anchor the pad to the scene's bottom-right corner, 12 px off the
	# gold frame. Its size is fixed by the buttons, so these offsets
	# pin it there on every window size.
	var dsize := dpad.get_combined_minimum_size()
	dpad.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	dpad.offset_left = -(dsize.x + 12)
	dpad.offset_top = -(dsize.y + 12)
	dpad.offset_right = -12
	dpad.offset_bottom = -12

	# Serif fonts (Noto Serif Display for the hero title, Noto Serif
	# for dialog text — both with full Cyrillic) activate
	# automatically once the TTFs are in res://assets/fonts/.
	var display_font := _try_font("res://assets/fonts/NotoSerifDisplay-Bold.ttf")
	if display_font != null:
		hero_label.add_theme_font_override("font", display_font)
	var body_font := _try_font("res://assets/fonts/NotoSerif-Regular.ttf")
	var body_bold := _try_font("res://assets/fonts/NotoSerif-Bold.ttf")
	var body_italic := _try_font("res://assets/fonts/NotoSerif-Italic.ttf")
	var body_bi := _try_font("res://assets/fonts/NotoSerif-BoldItalic.ttf")
	if body_font != null:
		dialog_label.add_theme_font_override("normal_font", body_font)
	if body_bold != null:
		dialog_label.add_theme_font_override("bold_font", body_bold)
	if body_italic != null:
		dialog_label.add_theme_font_override("italics_font", body_italic)
	if body_bi != null:
		dialog_label.add_theme_font_override("bold_italics_font", body_bi)

	get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_update_layout_mode")
	call_deferred("_apply_cell_size")
	call_deferred("_refresh_fonts")


# --- procedural brick texture (walls) --------------------------------------
# 256x256, eight courses per cell, bricks 64x32 (true brick rectangles,
# half the height of the previous square version). Running bond: every
# course is offset by half a brick relative to its neighbours, inside
# the tile as well as across tiles — the old version only offset
# alternate tile rows, so joints lined up into a grid inside each
# tile and the wall read as plain squares. The offset depends on
# course parity alone, so the pattern continues seamlessly over cell
# borders in both directions with a single texture. Shade variation
# is a hash of course/index, so it never flickers between refreshes.
var brick_texture_cache: Texture2D = null


func _brick_texture() -> Texture2D:
	if brick_texture_cache != null:
		return brick_texture_cache
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(SCENE_BG)
	var course_h := 32
	var brick_w := 64
	var gap := 4
	for course in 8:
		var y0 := course * course_h + gap / 2
		var y1 := (course + 1) * course_h - gap / 2
		var offset := 0 if course % 2 == 0 else -brick_w / 2
		var idx := 0
		var x := offset
		while x < s:
			var x0 := x + gap / 2
			var x1 := x + brick_w - gap / 2
			var shade := 0.97 + 0.03 * ((course * 3 + idx) % 3)
			var col := Color(BRICK_COLOR.r * shade, BRICK_COLOR.g * shade, BRICK_COLOR.b * shade, 1)
			for py in range(y0, y1):
				for px in range(max(x0, 0), min(x1, s)):
					img.set_pixel(px, py, col)
			idx += 1
			x += brick_w
	var tex := ImageTexture.create_from_image(img)
	brick_texture_cache = tex
	return tex


# --- procedural road texture ------------------------------------------------
# Black asphalt with white edge lines and a dashed centre line, drawn
# for one square cell. Adjacent cells' centred dashes (50% of the
# cell) join into a regular dashed line, so a strip of road cells
# reads as one road. One cached texture per direction.
var road_tex_h: Texture2D = null
var road_tex_v: Texture2D = null


func _road_texture(horizontal: bool) -> Texture2D:
	if horizontal and road_tex_h != null:
		return road_tex_h
	if not horizontal and road_tex_v != null:
		return road_tex_v
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(ROAD_COLOR)
	# Asphalt grain: a sparse speckle, slightly lighter/darker.
	for i in range(1800):
		var px := randi() % 256
		var py := randi() % 256
		var v := 0.14 + (randf() - 0.5) * 0.05
		img.set_pixel(px, py, Color(v, v, v + 0.01))
	var white := Color(0.92, 0.92, 0.90)
	if horizontal:
		_fill_rect(img, 0, 16, 256, 24, white)
		_fill_rect(img, 0, 232, 256, 240, white)
		_fill_rect(img, 64, 123, 192, 133, white)
	else:
		_fill_rect(img, 16, 0, 24, 256, white)
		_fill_rect(img, 232, 0, 240, 256, white)
		_fill_rect(img, 123, 64, 133, 192, white)
	var tex := ImageTexture.create_from_image(img)
	if horizontal:
		road_tex_h = tex
	else:
		road_tex_v = tex
	return tex


# --- procedural door sprite -------------------------------------------------
# A flat brown panel read as a placeholder, so doors get a drawn sprite
# instead: dark frame, vertical wood planks, two recessed panels and a
# brass knob. Same 256x256 stretched-to-cell treatment as the bricks.
var door_texture: Texture2D = null


func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for py in range(y0, y1):
		for px in range(x0, x1):
			img.set_pixel(px, py, col)


func _door_texture() -> Texture2D:
	if door_texture != null:
		return door_texture
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.29, 0.18, 0.10, 1)
	var wood := Color(0.48, 0.29, 0.15, 1)
	var wood_light := Color(0.52, 0.33, 0.18, 1)
	var seam := Color(0.37, 0.22, 0.11, 1)
	var panel_edge := Color(0.37, 0.22, 0.11, 1)
	# The door leaf is narrower than its cell (middle 60%, full
	# height) and the rest of the canvas stays transparent: the same
	# sprite serves both orientations — over bricks in a horizontal
	# wall, alone (frame-coloured cell behind it) in a vertical wall.
	var dx0 := 51
	var dx1 := 205
	_fill_rect(img, dx0, 0, dx1, s, frame)
	_fill_rect(img, dx0 + 14, 14, dx1 - 14, 242, wood)
	# Vertical planks.
	for x in [88, 111, 135, 158]:
		_fill_rect(img, x, 14, x + 2, 242, seam)
	# Two recessed panels with a lighter face.
	for py0 in [30, 138]:
		_fill_rect(img, 76, py0, 180, py0 + 84, panel_edge)
		_fill_rect(img, 78, py0 + 4, 178, py0 + 80, wood_light)
	# Brass knob.
	var kx := 171
	var ky := 128
	for py in range(ky - 10, ky + 11):
		for px in range(kx - 10, kx + 11):
			if (px - kx) * (px - kx) + (py - ky) * (py - ky) <= 100:
				img.set_pixel(px, py, Color(0.85, 0.70, 0.36, 1))
	var tex := ImageTexture.create_from_image(img)
	door_texture = tex
	return tex


# --- procedural arrow icons (font-independent, so Web never shows tofu) ---

func _in_triangle(px: float, py: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> bool:
	var d1 := (px - bx) * (ay - by) - (ax - bx) * (py - by)
	var d2 := (px - cx) * (by - cy) - (bx - cx) * (py - cy)
	var d3 := (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


func _arrow_icon(code: String) -> Texture2D:
	if code in arrow_icons:
		return arrow_icons[code]
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var col := Color(0.87, 0.89, 0.95, 1)
	for y in s:
		for x in s:
			var inside := false
			match code:
				"t":
					inside = _in_triangle(x, y, 48, 8, 16, 48, 80, 48) or (x >= 38 and x <= 58 and y >= 48 and y <= 88)
				"d":
					inside = _in_triangle(x, y, 48, 88, 16, 48, 80, 48) or (x >= 38 and x <= 58 and y >= 8 and y <= 48)
				"l":
					inside = _in_triangle(x, y, 8, 48, 48, 16, 48, 80) or (y >= 38 and y <= 58 and x >= 48 and x <= 88)
				"r":
					inside = _in_triangle(x, y, 88, 48, 48, 16, 48, 80) or (y >= 38 and y <= 58 and x >= 8 and x <= 48)
			if inside:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	arrow_icons[code] = tex
	return tex


# --- responsive layout + scene scaling + font scaling -----------------------

# Fixed sizes looked small on wide windows and on phones, so fonts grow
# with the viewport width (1.15x up to 1000 px, 1.6x beyond 1500 px):
# the raised floor keeps text readable on phones, where the viewport
# is counted in device pixels and everything renders physically small.
# Answer buttons are rebuilt on every refresh, so they pick the current
# scale up at creation; static labels are re-scaled here on resize.
func _font_scale() -> float:
	var w := get_viewport_rect().size.x
	if w <= 0:
		return 1.0
	# Narrow windows (phones in portrait): a higher scale so text
	# reads comfortably on a small screen. Wide windows use the
	# formula below unchanged: the 1.15 floor, the 1.2 cap (dialog
	# 30 px at 1920; 1.6 used to read too big).
	if w < NARROW_WIDTH:
		return 1.3
	return clamp(w / 1400.0, 1.15, 1.2)


func _scaled(base: int) -> int:
	return int(round(base * _font_scale()))


func _refresh_fonts() -> void:
	if hero_label == null:
		return
	hero_label.add_theme_font_size_override("font_size", _scaled(26))
	reset_toshik_button.add_theme_font_size_override("font_size", _scaled(22))
	reset_nastya_button.add_theme_font_size_override("font_size", _scaled(22))
	dialog_label.add_theme_font_size_override("normal_font_size", _scaled(25))
	dialog_label.add_theme_font_size_override("bold_font_size", _scaled(25))
	dialog_label.add_theme_font_size_override("italics_font_size", _scaled(25))
	dialog_label.add_theme_font_size_override("bold_italics_font_size", _scaled(25))
	text_input.add_theme_font_size_override("font_size", _scaled(22))
	submit_button.add_theme_font_size_override("font_size", _scaled(22))
	feedback_label.add_theme_font_size_override("font_size", _scaled(17))
	for code in ["i", "j"]:
		if code in dpad_buttons:
			(dpad_buttons[code] as Button).add_theme_font_size_override("font_size", _scaled(20))
	# Button tap targets follow the viewport: taller on narrow
	# windows (phones), standard on desktops. Recomputed here so a
	# rotation or window resize updates buttons built earlier.
	# Header buttons use the standard height; dialog-area buttons
	# (answers, inventory/journal, submit) are taller on narrow;
	# arrow buttons are square and bigger on narrow (their icons
	# scale via expand_icon).
	var bh := _button_min_height()
	var dbh := _dialog_button_min_height()
	var ds := _dpad_button_size()
	_set_button_height(reset_toshik_button, bh)
	_set_button_height(reset_nastya_button, bh)
	_set_button_height(submit_button, dbh)
	for code in dpad_buttons:
		var db := dpad_buttons[code] as Button
		if db == null:
			continue
		if code in ["i", "j"]:
			_set_button_height(db, dbh)
		else:
			db.custom_minimum_size = Vector2(ds, max(ds, bh))
	if dpad_pad != null:
		for child in dpad_pad.get_children():
			if not (child is Button):
				(child as Control).custom_minimum_size = Vector2(ds, ds)
	if answers_box != null:
		for child in answers_box.get_children():
			_set_button_height(child as Button, dbh)
	if inv_row != null:
		for child in inv_row.get_children():
			_set_button_height(child as Button, dbh)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_update_layout_mode")
		call_deferred("_apply_cell_size")
		call_deferred("_refresh_fonts")


func _on_viewport_resized() -> void:
	_update_layout_mode()
	_apply_cell_size()
	_refresh_fonts()


func _update_layout_mode() -> void:
	if sidebar == null or game_row == null or vbox == null:
		return
	var narrow := _is_narrow_window()
	if layout_init_done and narrow == layout_narrow:
		return
	layout_narrow = narrow
	layout_init_done = true
	# A layout-mode switch re-parents the sidebar; an overlaid sheet
	# must return to the vbox first, or the branches below would move
	# it to the wrong parent. Instant: rotation already jumps anyway.
	if dialog_expanded:
		if dialog_expand_tween != null and dialog_expand_tween.is_valid():
			dialog_expand_tween.kill()
		_finish_dialog_collapse()
	if narrow:
		# Controls under the scene: sidebar leaves the game row and
		# becomes the vbox's last child, sharing vertical space.
		if sidebar.get_parent() == game_row:
			game_row.remove_child(sidebar)
		if sidebar.get_parent() != vbox:
			vbox.add_child(sidebar)
		sidebar.custom_minimum_size = Vector2(0, 0)
		sidebar.size_flags_horizontal = SIZE_EXPAND_FILL
		sidebar.size_flags_vertical = SIZE_EXPAND_FILL
		sidebar.size_flags_stretch_ratio = 0.9
		game_row.size_flags_stretch_ratio = 1.2
		# The square scene cap is wide-mode only; in the stacked
		# layout the scene panel fills the row's full width again.
		scene_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		scene_panel.custom_minimum_size = Vector2(0, 0)
	else:
		if sidebar.get_parent() == vbox:
			vbox.remove_child(sidebar)
		if sidebar.get_parent() != game_row:
			game_row.add_child(sidebar)
		sidebar.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
		# The dialog zone takes all leftover row width on desktop:
		# long Nastya dialogs wrap into fewer lines and stop
		# scrolling the sidebar, instead of squeezing into 380 px.
		sidebar.size_flags_horizontal = SIZE_EXPAND_FILL
		sidebar.size_flags_vertical = SIZE_EXPAND_FILL
		sidebar.size_flags_stretch_ratio = 1.0
		game_row.size_flags_stretch_ratio = 1.0
		# The panel's width cap itself is set by _apply_cell_size.
		scene_panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	call_deferred("_apply_cell_size")
	call_deferred("_update_dialog_expansion")

func _update_dialog_expansion(instant: bool = false) -> void:
	# Mobile dialog sheet: in narrow layout, a dialog with no
	# movement arrows (a pure choice list) grows the sidebar into
	# a full sheet that covers the scene, so every answer fits
	# without scrolling. Movement dialogs keep the stacked
	# scene+sidebar (the player needs the scene and the arrows to
	# walk), and photo dialogs keep the photo visible. The sheet
	# is the sidebar itself, reparented to the root and slid up
	# over the scene (its panel is opaque); the vbox layout is
	# untouched, so there is no cell-size fight: the scene simply
	# sits behind the sheet until the dialog collapses.
	if sidebar == null or game_row == null or vbox == null:
		return
	if not layout_init_done:
		return
	# Not laid out yet (startup): retry after the first layout.
	if sidebar.get_global_rect().size == Vector2.ZERO or game_row.get_global_rect().size == Vector2.ZERO:
		call_deferred("_update_dialog_expansion")
		return
	var want := _is_narrow_window() and not showing_photo
	if want:
		for code in ["t", "d", "l", "r"]:
			if code in dpad_buttons and not (dpad_buttons[code] as Button).disabled:
				want = false
				break
	var tween_running := dialog_expand_tween != null and dialog_expand_tween.is_valid() and dialog_expand_tween.is_running()
	if want == dialog_expanded and not tween_running:
		return
	if dialog_expand_tween != null and dialog_expand_tween.is_valid():
		dialog_expand_tween.kill()
	if want:
		# Pin the scene row's height before the sidebar leaves the
		# vbox: without this, the row (the only expanding child
		# left) grows to the full vbox height, and the centred grid
		# jumps down (a big beige indent appears above the map)
		# for the whole time the sheet is up, then jumps back on
		# collapse. The pin equals the settled stacked height, so
		# the scene behind the sheet does not move at all; it is
		# released in _finish_dialog_collapse. This also fixes the
		# photo-dialog softlock: a photo opened from the sheet
		# used to lock the grown panel tall (its minimum tracks
		# the panel size), pushing the sidebar off-screen.
		game_row.custom_minimum_size = Vector2(game_row.custom_minimum_size.x, game_row.size.y)
		game_row.size_flags_vertical = SIZE_FILL
		var target_top := game_row.get_global_rect().position.y
		if sidebar.get_parent() != self:
			dialog_expand_from_top = sidebar.get_global_rect().position.y
			sidebar.get_parent().remove_child(sidebar)
			add_child(sidebar)
			sidebar.set_anchors_preset(PRESET_FULL_RECT)
			sidebar.offset_left = 14
			sidebar.offset_right = -14
			sidebar.offset_bottom = -10
			sidebar.offset_top = dialog_expand_from_top
		dialog_expanded = true
		if instant:
			sidebar.offset_top = target_top
		else:
			dialog_expand_tween = create_tween()
			dialog_expand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			dialog_expand_tween.tween_property(sidebar, "offset_top", target_top, 0.3)
	else:
		if sidebar.get_parent() == self:
			if instant:
				_finish_dialog_collapse()
			else:
				dialog_expand_tween = create_tween()
				dialog_expand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				dialog_expand_tween.tween_property(sidebar, "offset_top", dialog_expand_from_top, 0.3)
				dialog_expand_tween.finished.connect(_finish_dialog_collapse, CONNECT_ONE_SHOT)
		else:
			dialog_expanded = false


func _finish_dialog_collapse() -> void:
	# Back to the vbox's last child (the narrow stacked slot); the
	# wide branch of _update_layout_mode moves it on if needed.
	# Cells were sized for the overlaid (grown) scene, so refit
	# them for the restored panel on the next frame.
	if sidebar.get_parent() == self:
		remove_child(sidebar)
		vbox.add_child(sidebar)
	# Release the pin set when the sheet expanded: the row goes
	# back to sharing the vbox by ratio (which equals the pin,
	# so releasing it moves nothing).
	game_row.custom_minimum_size = Vector2(game_row.custom_minimum_size.x, 0)
	game_row.size_flags_vertical = SIZE_EXPAND_FILL
	dialog_expanded = false
	call_deferred("_apply_cell_size")


func _apply_cell_size() -> void:
	if scene_grid == null or scene_panel == null or scene_cols <= 0 or scene_rows <= 0:
		return
	# Wide windows only: cap the scene panel at a square, so on a
	# wide monitor it does not stretch across the whole width and
	# push the sidebar far to the right. The sidebar then sits
	# right next to the scene; the leftover width stays empty on the
	# far right.
	#
	# The cap AND the cell size derive from the viewport, never
	# from the panel's current size: the panel's size follows the
	# grid (content) as much as the grid follows the panel, and
	# deriving the cell from the panel made the layout bistable —
	# a transient tall panel could flip it to a zoomed fixed point
	# (panel tall -> cell huge -> panel taller) that no later run
	# corrected, which is exactly the desktop zoom bug.
	# Chrome, wide mode: margins 14/10, header 56, divider 2,
	# vbox separations 10+10, sidebar 380, row separation 12.
	var cell := FALLBACK_CELL
	if not layout_narrow and game_row != null and sidebar != null:
		var vp := get_viewport_rect().size
		var row_w: float = vp.x - 28.0
		var row_h: float = vp.y - 98.0
		var target_w: float = min(row_w - SIDEBAR_WIDTH - 12.0, row_h)
		if target_w > 0 and scene_panel.custom_minimum_size.x != target_w:
			scene_panel.custom_minimum_size = Vector2(target_w, 0)
			call_deferred("_apply_cell_size")
		if target_w > 0:
			cell = int(min((target_w - 8.0) / scene_cols, (row_h - 8.0) / scene_rows))
			cell = max(cell, MIN_CELL)
	else:
		var avail := scene_panel.size
		if avail.x > 0 and avail.y > 0:
			cell = int(min(avail.x / scene_cols, avail.y / scene_rows))
			cell = max(cell, MIN_CELL)
	for child in scene_grid.get_children():
		child.custom_minimum_size = Vector2(cell, cell)
	for entry in small_sprites:
		entry["node"].custom_minimum_size = Vector2(cell / 2, cell / 2)
	for entry in card_sprites:
		# Photo card: 0.62 x 0.51 of a cell (matches the shoe's own
		# aspect), rotated -0.30 rad (about 17 degrees, clearly
		# visible even on a small card); the rotated bounding box
		# (0.74 x 0.67) still fits its cell. The shoe sits inside
		# with a small ivory margin, like a picture.
		var cw := cell * 0.62
		var ch := cell * 0.51
		var m := cell * 0.06
		var card: Control = entry["card"]
		card.custom_minimum_size = Vector2(cw, ch)
		card.pivot_offset = Vector2(cw / 2, ch / 2)
		var shadow: ColorRect = entry["shadow"]
		shadow.position = Vector2(cell * 0.03, cell * 0.045)
		shadow.size = Vector2(cw, ch)
		var paper: Panel = entry["paper"]
		paper.position = Vector2.ZERO
		paper.size = Vector2(cw, ch)
		var shoe: TextureRect = entry["shoe"]
		shoe.position = Vector2(m, m)
		shoe.custom_minimum_size = Vector2(cw - 2 * m, ch - 2 * m)
	for entry in scaled_sprites:
		var s: float = entry["scale"]
		entry["node"].custom_minimum_size = Vector2(cell * s, cell * s)
		# Squash pivot at the feet: the head dips down, never up.
		entry["node"].pivot_offset = Vector2(cell * s / 2, cell * s)
	if fog_overlay == null:
		return
	# Fog overlay: one dark column per run, at most 2 cells tall and
	# never past the grid's bottom edge. It used to run to the panel's
	# bottom edge, which stuck out past the map into the panel's empty
	# gap in tall portrait windows and looked like a stray stripe.
	for child in fog_overlay.get_children():
		fog_overlay.remove_child(child)
		child.free()
	fog_overlay.visible = not fog_runs.is_empty() and not showing_photo
	if photo_rect != null and showing_photo:
		photo_rect.custom_minimum_size = Vector2(max(scene_panel.size.x - 8, 0), max(scene_panel.size.y - 8, 0))
	if fog_runs.is_empty():
		return
	var grid_h := scene_rows * cell
	fog_overlay.custom_minimum_size = Vector2(scene_cols * cell, grid_h)
	for run in fog_runs:
		var h: int = min(2 * cell, grid_h - run["row"] * cell)
		if h <= 0:
			continue
		var rect := Panel.new()
		rect.mouse_filter = MOUSE_FILTER_IGNORE
		rect.add_theme_stylebox_override("panel", _panel_style(Color(0.2, 0.17, 0.26), Color(0, 0, 0, 0), 0))
		rect.position = Vector2(run["col"] * cell, run["row"] * cell)
		rect.size = Vector2(run["span"] * cell, h)
		fog_overlay.add_child(rect)


func _set_fit_content(label: RichTextLabel) -> void:
	# Property name differs across Godot versions (fit_content in 4.3 and
	# 4.7, fit_content_height in some builds in between); set whichever
	# exists, otherwise fall back to a fixed minimum height.
	var names: Array = []
	for prop in label.get_property_list():
		names.append(prop["name"])
	if "fit_content_height" in names:
		label.set("fit_content_height", true)
	elif "fit_content" in names:
		label.set("fit_content", true)
	else:
		label.custom_minimum_size = Vector2(0, 140)


# --- refresh ------------------------------------------------------------------

# A merged shape: a corner is rounded only when it lies on the shape's
# outer silhouette, i.e. when neither of its two neighbouring directions
# continues the same shape. Inner and edge corners stay square so
# neighbouring cells join seamlessly.
func _merged_style(bg: Color, up: bool, down: bool, left: bool, right: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	var r := 16
	style.corner_radius_top_left = r if (not up and not left) else 0
	style.corner_radius_top_right = r if (not up and not right) else 0
	style.corner_radius_bottom_left = r if (not down and not left) else 0
	style.corner_radius_bottom_right = r if (not down and not right) else 0
	return style


func _cell_style(emoji: String, is_player: bool, up_same: bool, down_same: bool, left_same: bool, right_same: bool) -> StyleBoxFlat:
	# Styled by emoji, because the engine's visible window is emoji-only.
	# Wall/road share one emoji each, which is all merging needs. No
	# emoji glyph is ever drawn as text: doors and marks are coloured
	# panels, so the web build cannot show tofu for them.
	if emoji == "⬛️":
		# Flat mortar background; the brick texture child (added in
		# _refresh) covers it. Square corners: bricks are square, and
		# the texture tiles seamlessly across cells as it is.
		return _panel_style(SCENE_BG, Color(0, 0, 0, 0), 0)
	if emoji == "🕳":
		# Square asphalt panel; the markings texture child (added
		# in _refresh) draws the road on top of it. The old merged
		# rounded tan path is gone: a road reads as one continuous
		# strip, like the brick walls read as one wall.
		return _panel_style(ROAD_COLOR, Color(0, 0, 0, 0), 0)
	if emoji == "🚪":
		# Transparent: the narrow door's sides must show the scene
		# floor, not a brown frame — the brown side strips read as a
		# botched door. (The brick underlay covers the cell anyway
		# for horizontal-wall doors.)
		return _panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	if emoji == "✖️":
		# Square, full-cell fog: no rounding, so a run of fog cells
		# reads as one solid darkness running down to the scene's
		# bottom edge, not as rounded tiles floating in the corridor.
		return _panel_style(Color(0.2, 0.17, 0.26), Color(0, 0, 0, 0), 0)
	# Everything else (floor, hero, characters, items) sits directly on
	# the scene panel's background: no tile, no frame, no glow ring.
	return _panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)


func _sprite_frames(name: String) -> Array:
	# AI sprites take priority; procedural sprites in assets/sprites/
	# stay as a fallback for any name the AI set does not cover.
	var frames: Array = []
	for folder in ["res://assets/sprites_ai/", "res://assets/sprites/"]:
		for i in range(3):
			var path: String = folder + "%s_%d.png" % [name, i]
			if ResourceLoader.exists(path):
				frames.append(load(path))
			else:
				break
		if frames.size() > 0:
			break
	return frames


func _refresh() -> void:
	var dlg := engine.current_dialog()
	hero_label.text = "Герой: " + engine.hero_name()
	var hero_frames := _sprite_frames(SPRITES.get(dlg.get("player_icon", "O"), "toshik"))
	if hero_frames.size() > 0:
		hero_portrait.texture = hero_frames[0]
	var message := _markdown_to_bbcode(_strip_emoji(engine.current_message()))
	var answers := engine.available_answers()
	var has_photo := "photo" in dlg

	# Scene tiles. Free immediately, not queue_free: the rebuild
	# below runs synchronously, and queued cells would still be
	# laid out with the new ones for the rest of the frame — a
	# transient double grid that fed the panel-size feedback loop
	# behind the desktop zoom bug (panel tall -> cell huge ->
	# panel taller, freezing at a zoomed fixed point).
	for child in scene_grid.get_children():
		child.free()
	animated_tiles = []
	small_sprites = []
	card_sprites = []
	scaled_sprites = []
	squash_sprites = []
	var fog_cells: Array = []
	var tiles: Array = engine.visible_tiles()
	scene_cols = tiles[0].size()
	scene_rows = tiles.size()
	scene_grid.columns = scene_cols
	var centre := tiles.size() / 2
	var dlg_hero: String = dlg.get("player_icon", "O")
	for y in tiles.size():
		for x in tiles[y].size():
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(FALLBACK_CELL, FALLBACK_CELL)
			var is_player: bool = x == centre and y == centre
			var emoji: String = tiles[y][x]
			if emoji == "✖️":
				fog_cells.append(Vector2i(x, y))
			# Neighbours come from the full map, not just the visible
			# window: a door at the window's edge otherwise reads as
			# vertical until the window shifts and its neighbours
			# appear (the start corridor door showed no bricks for
			# exactly this reason, although its wall is horizontal).
			var same := func(nx: int, ny: int) -> bool:
				var mx := engine.pos.x + nx - centre
				var my := engine.pos.y + ny - centre
				return engine.emoji_at(mx, my) == emoji
			cell.add_theme_stylebox_override("panel", _cell_style(
				emoji, is_player,
				same.call(x, y - 1), same.call(x, y + 1),
				same.call(x - 1, y), same.call(x + 1, y)))
			scene_grid.add_child(cell)
			# Walls get a brick texture child (running bond, offset
			# per course); roads, bare floor, doors and marks are
			# pure background shapes: nothing is drawn inside them
			# (their emoji are never rendered as text, so no tofu).
			if not is_player and emoji == "⬛️":
				var brick := TextureRect.new()
				brick.texture = _brick_texture()
				brick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				brick.stretch_mode = TextureRect.STRETCH_SCALE
				cell.add_child(brick)
				continue
			if not is_player and emoji == "🕳":
				# The road (Nastya's final road, rows 21-22, is the
				# only '=' strip on the map): black asphalt with
				# white markings, running along the road's direction
				# from the full map, like doors. Isolated cells stay
				# plain asphalt (panel only, no texture).
				var horiz: bool = same.call(x - 1, y) or same.call(x + 1, y)
				var vert: bool = same.call(x, y - 1) or same.call(x, y + 1)
				if horiz or vert:
					var road := TextureRect.new()
					road.texture = _road_texture(horiz)
					road.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					road.stretch_mode = TextureRect.STRETCH_SCALE
					cell.add_child(road)
				continue
			if not is_player and emoji == "🚪":
				# A door in a horizontal wall (wall cells left and
				# right) gets the brick texture underneath, so the
				# wall reads as continuing past the narrow door on
				# both sides; a door in a vertical wall gets just
				# the narrow door. One door sprite serves both.
				# Neighbours come from the full map: a door at the
				# window's edge used to read as vertical until the
				# window shifted and its neighbours appeared.
				var wall_left: bool = engine.emoji_at(engine.pos.x + x - centre - 1, engine.pos.y + y - centre) == "⬛️"
				var wall_right: bool = engine.emoji_at(engine.pos.x + x - centre + 1, engine.pos.y + y - centre) == "⬛️"
				if wall_left and wall_right:
					var brick := TextureRect.new()
					brick.texture = _brick_texture()
					brick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					brick.stretch_mode = TextureRect.STRETCH_SCALE
					cell.add_child(brick)
				var door := TextureRect.new()
				door.texture = _door_texture()
				door.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				door.stretch_mode = TextureRect.STRETCH_SCALE
				cell.add_child(door)
				continue
			if not is_player and emoji in ["🕳", "▫️", "✖️"]:
				continue
			if is_player:
				var hero_name: String = SPRITES.get(dlg_hero, "toshik")
				var frames := _sprite_frames(hero_name)
				if frames.size() > 0:
					var sprite := TextureRect.new()
					sprite.texture = frames[0]
					sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					# Slightly smaller than the cell, like every other
					# character (see SPRITE_SCALE): full height puts
					# the head exactly on the cell border.
					var hs: float = SPRITE_SCALE.get(hero_name, CHAR_SPRITE_SCALE)
					var hwrap := CenterContainer.new()
					sprite.custom_minimum_size = Vector2(FALLBACK_CELL * hs, FALLBACK_CELL * hs)
					hwrap.add_child(sprite)
					cell.add_child(hwrap)
					scaled_sprites.append({"node": sprite, "scale": hs})
					# Squash, not frame cycling: the frames differ
					# by 12 px and that bobbed the figure upward.
					squash_sprites.append({"node": sprite, "phase": squash_sprites.size() * 0.9})
				else:
					_add_emoji_cell(cell, tiles[y][x])
			else:
				# Non-player cells: try a sprite by emoji is not possible,
				# so match by the underlying map char via the engine's
				# visible window is emoji-only; sprites for NPCs are wired
				# through _sprite_for_emoji below.
				var sprite_name := _sprite_for_emoji(tiles[y][x])
				if sprite_name != "":
					var frames := _sprite_frames(sprite_name)
					if frames.size() > 0:
						var sprite := TextureRect.new()
						sprite.texture = frames[0]
						sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
						sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						if sprite_name in CARD_ITEM_SPRITES:
							# A note/photo card lying on the floor: the
							# sprite PNG is untouched, it is composited
							# onto a procedural ivory card (rotated a
							# touch, soft shadow). Exact sizes are fixed
							# up in _apply_cell_size like other sprites.
							var cwrap := CenterContainer.new()
							var card := Control.new()
							card.rotation = -0.30
							var shadow := ColorRect.new()
							shadow.color = Color(0, 0, 0, 0.25)
							card.add_child(shadow)
							var paper := Panel.new()
							paper.add_theme_stylebox_override("panel", _panel_style(PARCHMENT, Color(0.55, 0.45, 0.30), 4))
							card.add_child(paper)
							card.add_child(sprite)
							cwrap.add_child(card)
							cell.add_child(cwrap)
							card_sprites.append({"card": card, "shadow": shadow, "paper": paper, "shoe": sprite})
						elif sprite_name in ITEM_SPRITES:
							# Half-size, centered in its cell; the
							# exact size is fixed up in _apply_cell_size.
							var wrap := CenterContainer.new()
							sprite.custom_minimum_size = Vector2(FALLBACK_CELL / 2, FALLBACK_CELL / 2)
							wrap.add_child(sprite)
							cell.add_child(wrap)
							small_sprites.append({"node": sprite, "cell": cell})
						elif sprite_name == "fire":
							cell.add_child(sprite)
						elif sprite_name in BIG_ITEM_SPRITES:
							var bs: float = BIG_ITEM_SPRITES[sprite_name]
							var bwrap := CenterContainer.new()
							sprite.custom_minimum_size = Vector2(FALLBACK_CELL * bs, FALLBACK_CELL * bs)
							bwrap.add_child(sprite)
							cell.add_child(bwrap)
							scaled_sprites.append({"node": sprite, "scale": bs})
						else:
							# Characters: scaled down, centered in
							# its cell; the exact size is fixed up in
							# _apply_cell_size. Default 0.9, with
							# SPRITE_SCALE overrides (zags 0.8).
							var s: float = SPRITE_SCALE.get(sprite_name, CHAR_SPRITE_SCALE)
							var swrap := CenterContainer.new()
							sprite.custom_minimum_size = Vector2(FALLBACK_CELL * s, FALLBACK_CELL * s)
							swrap.add_child(sprite)
							cell.add_child(swrap)
							scaled_sprites.append({"node": sprite, "scale": s})
						# Fire keeps flickering through its frames;
						# characters squash instead of hopping.
						# (Items and big items stay static.)
						if sprite_name == "fire":
							if frames.size() > 1:
								animated_tiles.append({"node": sprite, "frames": frames, "interval": 0.18, "elapsed": 0.0, "idx": 0})
						elif sprite_name not in ITEM_SPRITES and sprite_name not in BIG_ITEM_SPRITES and sprite_name not in CARD_ITEM_SPRITES:
							squash_sprites.append({"node": sprite, "phase": squash_sprites.size() * 0.9})
					else:
						_add_emoji_cell(cell, tiles[y][x])
				else:
					_add_emoji_cell(cell, tiles[y][x])

	# Fog runs: per column, the top fog cell; adjacent columns sharing
	# the same top row merge into one run. _apply_cell_size turns each
	# run into a dark column reaching the panel's bottom edge.
	var fog_top := {}
	for c in fog_cells:
		var col: int = c.x
		if col not in fog_top or c.y < fog_top[col]:
			fog_top[col] = c.y
	var fog_cols_sorted := fog_top.keys()
	fog_cols_sorted.sort()
	fog_runs = []
	for col in fog_cols_sorted:
		var row: int = fog_top[col]
		if fog_runs.size() > 0:
			var last: Dictionary = fog_runs[fog_runs.size() - 1]
			if last["col"] + last["span"] == col and last["row"] == row:
				last["span"] += 1
				continue
		fog_runs.append({"col": col, "span": 1, "row": row})

	_apply_cell_size()

	# No modal at all: a photo dialog replaces the whole scene with the
	# photo, and the dialog and answers stay in the sidebar exactly
	# like any other dialog. This also fixes photo dialogs with hidden
	# answers (Demianov3): the modal never showed the free-text field,
	# so its riddle could only be skipped, never answered by typing.
	sidebar.visible = true
	if has_photo:
		for child in scene_grid.get_children():
			child.queue_free()
		animated_tiles = []
		small_sprites = []
		card_sprites = []
		scaled_sprites = []
		squash_sprites = []
		showing_photo = true
		photo_rect.texture = load("res://assets/" + dlg["photo"]) as Texture2D
		photo_rect.custom_minimum_size = Vector2(max(scene_panel.size.x - 8, 0), max(scene_panel.size.y - 8, 0))
		photo_rect.visible = true
		fog_overlay.visible = false
	else:
		showing_photo = false
		photo_rect.visible = false
	dialog_label.text = message
	input_block.visible = not engine.hidden_answers().is_empty()
	feedback_label.text = ""
	text_input.text = ""
	_sync_native_answer_input()
	for child in answers_box.get_children():
		child.queue_free()
	var has_move := false
	for answer in answers:
		if answer["message"] in MOVE_CODES:
			has_move = true
		else:
			var button := Button.new()
			button.text = _answer_label(answer["message"])
			button.focus_mode = FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			# Buttons do NOT wrap by default: a long answer's
			# minimum width (782 px measured for one) widened the
			# whole sidebar and shrank the scene. Wrapping pins
			# the sidebar at 380 px; only a window resize reflows.
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.add_theme_font_size_override("font_size", _scaled(23))
			_style_button(button)
			# Answer text is left-aligned: it needs a left pad so it
			# stops hugging the gold border (header buttons got the
			# same 18 px earlier).
			_pad_button_sides(button, 18)
			_set_button_height(button, _dialog_button_min_height())
			button.pressed.connect(_on_answer.bind(answer))
			answers_box.add_child(button)
	dpad_block.visible = has_move
	# The arrow pad hides with the block when a dialog offers no moves.
	if dpad_pad != null:
		dpad_pad.visible = has_move
	for code in dpad_buttons:
		var found := false
		for answer in answers:
			if answer["message"] == code:
				found = true
				break
		var button: Button = dpad_buttons[code]
		button.disabled = not found
		button.modulate = Color(1, 1, 1, 1) if found else Color(1, 1, 1, 0.35)
	_release_text_focus()
	# Mobile: tapping the field inside the scrollable sidebar often
	# fails to focus it (the list intercepts the tap as a swipe), so
	# typed text goes nowhere. Focus it as soon as a hidden-answer
	# dialog opens: the virtual keyboard opens at once, in the tap's
	# own gesture, and no tap on the field is needed at all.
	if sidebar.visible and input_block.visible and not native_input_active:
		text_input.grab_focus()
	# Choice dialogs on phones grow into a full sheet (see below).
	_update_dialog_expansion()


func _release_text_focus() -> void:
	# Keep keyboard focus in the input only while it is usable;
	# otherwise WASD would stay blocked after the dialog changed.
	if get_viewport().gui_get_focus_owner() == text_input:
		if not (sidebar.visible and input_block.visible):
			text_input.release_focus()


func _on_text_submit(_text: String = "") -> void:
	var typed := text_input.text.strip_edges().to_lower()
	if typed == "":
		return
	# Same rule as the original (StringExtensions.SameAs): trim and
	# case-insensitive compare against the hidden answers.
	for answer in engine.hidden_answers():
		if (answer["message"] as String).strip_edges().to_lower() == typed:
			text_input.release_focus()
			_on_answer(answer)
			return
	feedback_label.text = "Демьянов не понял — попробуй ещё раз."
	text_input.grab_focus()
	text_input.select_all()


func _setup_native_answer_callback() -> void:
	# Web only: hand JS a callback so the native answer bar can
	# submit typed text back into the game. Note the gate is
	# OS.has_feature("web"), NOT Engine.has_singleton: the
	# JavaScriptBridge singleton exists on every platform, but
	# off-web its methods just return null (verified headless:
	# get_interface("window") is null there). Non-web builds and
	# headless tests skip this entirely, keeping the LineEdit path.
	if not OS.has_feature("web"):
		return
	native_answer_callback = JavaScriptBridge.create_callback(_on_native_answer)
	JavaScriptBridge.get_interface("window").__tnAnswerCallback = native_answer_callback


func _sync_native_answer_input() -> void:
	# Web-mobile only: hidden-answer dialogs type into a real HTML
	# <input> (the native bar in web_shell.html) instead of the
	# game's LineEdit, whose web bridge drops composed text from
	# virtual keyboards on Android: focus opens, autocomplete runs,
	# but nothing lands. The bar is shown only on touch devices
	# (its JS returns false on desktops, keeping the LineEdit).
	# Non-web builds skip this entirely.
	if not OS.has_feature("web"):
		return
	var window_obj = JavaScriptBridge.get_interface("window")
	if window_obj == null:
		native_input_active = false
		input_row.visible = true
		return
	if input_block.visible:
		var shown = window_obj.__tnShowAnswer()
		native_input_active = shown == true
		input_row.visible = not native_input_active
		if native_input_active and get_viewport().gui_get_focus_owner() == text_input:
			text_input.release_focus()
	else:
		window_obj.__tnHideAnswer()
		native_input_active = false
		input_row.visible = true


func _on_native_answer(args: Array) -> void:
	# Same rule as _on_text_submit, but the text comes from the
	# native bar (its JS passes the value as the first argument).
	# On a correct answer the refresh below re-syncs (hiding the
	# bar when the next dialog has no hidden answers); on a wrong
	# one the bar stays, refocused with its text selected.
	if args.is_empty():
		return
	var typed := (args[0] as String).strip_edges().to_lower()
	if typed == "":
		return
	for answer in engine.hidden_answers():
		if (answer["message"] as String).strip_edges().to_lower() == typed:
			_on_answer(answer)
			return
	feedback_label.text = "Демьянов не понял — попробуй ещё раз."
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").__tnFocusAnswer()


func _add_emoji_cell(cell: PanelContainer, emoji: String) -> void:
	var label := Label.new()
	label.text = emoji
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	cell.add_child(label)


func _sprite_for_emoji(emoji: String) -> String:
	# The engine's visible window is emoji-only, so map NPCs back to
	# sprites through the emoji table (data/quest.json "emoji" is the
	# inverse of this map in practice: each NPC has a unique emoji).
	var table := engine.data["emoji"] as Dictionary
	for ch in SPRITES:
		if table.get(ch, ch) == emoji and ch not in ["O", "N"]:
			return SPRITES[ch]
	return ""


func _answer_label(message: String) -> String:
	if message in MOVE_WORDS:
		return MOVE_WORDS[message]
	return _strip_emoji(message).replace("*", "").replace("_", "").strip_edges()


# On Web there is no system font fallback, so any emoji in a dialog or
# answer text renders as a tofu box. Strip emoji codepoints there (the
# words stay); on desktop the texts are shown untouched, emoji included.
func _strip_emoji(text: String) -> String:
	if OS.get_name() != "Web":
		return text
	var out := ""
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp == 0x200D or (cp >= 0xFE00 and cp <= 0xFE0F) \
				or (cp >= 0x2600 and cp <= 0x27BF) \
				or (cp >= 0x2B00 and cp <= 0x2BFF) \
				or (cp >= 0x1F000 and cp <= 0x1FAFF):
			continue
		out += text[i]
	return out.replace("  ", " ")


func _on_answer(answer: Dictionary) -> void:
	engine.apply_answer(answer)
	engine.save()
	_refresh()


func _on_move(code: String) -> void:
	for answer in engine.available_answers():
		if answer["message"] == code:
			_on_answer(answer)
			break


func _on_reset_toshik() -> void:
	engine.new_game()
	engine.save()
	_refresh()


func _on_reset_nastya() -> void:
	engine.new_game_as_nastya()
	engine.save()
	_refresh()


func _input(event: InputEvent) -> void:
	# While the player types an answer, letters must go to the input
	# only — otherwise a typed "В" (physical D key) would move the hero.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ev := event as InputEventKey
		# Physical key, not logical keycode: with a Russian layout the
		# same physical key produces Ц instead of W, so keycode-based
		# WASD silently stops working. Physical keys are layout-free
		# (and identical to keycode for arrows). Defining the actions
		# in project settings would need the same physical_keycode
		# values, so the fix belongs here either way.
		var key := ev.physical_keycode
		if key == 0:
			key = ev.keycode
		if key in MOVE_KEYS:
			_on_move(MOVE_KEYS[key])


func _markdown_to_bbcode(text: String) -> String:
	# The original texts use Telegram Markdown: *bold* and _italic_.
	var out := text
	var bold := RegEx.new()
	bold.compile("\\*([^*]+)\\*")
	out = bold.sub(out, "[b]$1[/b]", true)
	var italic := RegEx.new()
	italic.compile("_([^_]+)_")
	out = italic.sub(out, "[i]$1[/i]", true)
	return out
