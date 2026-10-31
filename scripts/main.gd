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
var reset_button: Button
var scene_panel: PanelContainer
var scene_grid: GridContainer
var fog_overlay: Control
var fog_runs: Array = []
var sidebar: PanelContainer
var dialog_card: PanelContainer
var hero_portrait: TextureRect
var dialog_label: RichTextLabel
var input_block: VBoxContainer
var text_input: LineEdit
var submit_button: Button
var feedback_label: Label
var answers_box: VBoxContainer
var dpad_block: VBoxContainer
var dpad_buttons := {}
var photo_rect: TextureRect
var showing_photo := false

var animated_tiles: Array = []
var small_sprites: Array = []
var anim_time := 0.0
var arrow_icons := {}
var scene_cols := 0
var scene_rows := 0
var layout_narrow := false
var layout_init_done := false

const FALLBACK_CELL := 64
const MIN_CELL := 40
# Light scene palette (the user picked a light scene so the remaining
# white sprite fringe blends in instead of glowing on dark tiles).
# The floor is the scene panel's own background, not a tile at all.
const SCENE_BG := Color(0.91, 0.89, 0.83)
const ROAD_COLOR := Color(0.78, 0.73, 0.62)
const DOOR_COLOR := Color(0.42, 0.29, 0.17)
const DOOR_BORDER := Color(0.26, 0.17, 0.09)
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
# Pickup items render at half cell size; characters (and fire) stay full.
const ITEM_SPRITES := ["monocle", "extinguisher", "boots", "key", "shoe", "taxofon"]
# Map character -> sprite set in assets/sprites/ (<name>_0.png, _1, _2).
const SPRITES := {
	"O": "toshik", "N": "nastya", "Z": "zags", "J": "jacob",
	"k": "kolyan", "U": "kolyan", "K": "sedosh", "S": "sokrat",
	"B": "bartender", "P": "policeman", "c": "crowd", "C": "crowd",
	"T": "crowd", "G": "genich", "R": "repa", "o": "okusheva",
	"F": "fire", "M": "monocle", "f": "extinguisher", "b": "boots",
	"?": "key", "v": "shoe", "z": "taxofon",
}
func _ready() -> void:
	engine.load_data("res://data/quest.json")
	_build_ui()
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


func _try_font(path: String) -> FontFile:
	# Serif fonts activate automatically once the TTFs are in
	# res://assets/fonts/; until then the default font is used, so a
	# build without the (binary, user-pushed) font files still works.
	if ResourceLoader.exists(path):
		return load(path) as FontFile
	return null


func _parchment_style() -> StyleBoxTexture:
	# 256x256 ivory parchment with a double gold border and small gold
	# corner flourishes, used as a 9-slice stylebox so the corners never
	# distort however large the dialog card grows.
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
	var corners: Array = [[30, 30, 1, 1], [225, 30, -1, 1], [30, 225, 1, -1], [225, 225, -1, -1]]
	for c in corners:
		var cx: int = c[0]
		var cy: int = c[1]
		var sx: int = c[2]
		var sy: int = c[3]
		for dx in range(-5, 6):
			for dy in range(-5, 6):
				if abs(dx) + abs(dy) <= 5:
					img.set_pixel(cx + dx, cy + dy, GOLD)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if dx * dx + dy * dy <= 4:
					img.set_pixel(cx + sx * 13 + dx, cy + sy * 13 + dy, GOLD)
	var tex := ImageTexture.create_from_image(img)
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.expand_margin_left = 48
	style.expand_margin_right = 48
	style.expand_margin_top = 48
	style.expand_margin_bottom = 48
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style


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
	reset_button = Button.new()
	reset_button.text = "Начать заново"
	reset_button.focus_mode = FOCUS_NONE
	reset_button.add_theme_font_size_override("font_size", 20)
	_style_button(reset_button)
	reset_button.pressed.connect(_on_reset)
	header.add_child(reset_button)
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
	dialog_card.add_theme_stylebox_override("panel", _parchment_style())
	dialog_card.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_box.add_child(dialog_card)
	var dialog_margin := MarginContainer.new()
	dialog_margin.add_theme_constant_override("margin_left", 16)
	dialog_margin.add_theme_constant_override("margin_right", 16)
	dialog_margin.add_theme_constant_override("margin_top", 14)
	dialog_margin.add_theme_constant_override("margin_bottom", 14)
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
	var input_row := HBoxContainer.new()
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

	# D-pad block: inventory/journal as text buttons above the arrow pad.
	dpad_block = VBoxContainer.new()
	dpad_block.add_theme_constant_override("separation", 8)
	dpad_block.size_flags_horizontal = SIZE_EXPAND_FILL
	sidebar_box.add_child(dpad_block)
	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 8)
	dpad_block.add_child(inv_row)
	for code in ["i", "j"]:
		var button := Button.new()
		button.text = MOVE_WORDS[code]
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.focus_mode = FOCUS_NONE
		button.add_theme_font_size_override("font_size", 18)
		_style_button(button)
		button.pressed.connect(_on_move.bind(code))
		inv_row.add_child(button)
		dpad_buttons[code] = button
	var dpad_center := CenterContainer.new()
	dpad_block.add_child(dpad_center)
	var dpad := GridContainer.new()
	dpad.columns = 3
	dpad.add_theme_constant_override("h_separation", 4)
	dpad.add_theme_constant_override("v_separation", 4)
	dpad_center.add_child(dpad)
	# Row 1: (empty) / up / (empty); row 2: left / centre / right;
	# row 3: (empty) / down / (empty).
	var dpad_layout := ["", "t", "", "l", "", "r", "", "d", ""]
	for code in dpad_layout:
		if code == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(52, 52)
			dpad.add_child(spacer)
		else:
			var button := Button.new()
			button.icon = _arrow_icon(code)
			button.expand_icon = true
			button.custom_minimum_size = Vector2(52, 52)
			button.focus_mode = FOCUS_NONE
			_style_button(button)
			button.pressed.connect(_on_move.bind(code))
			dpad.add_child(button)
			dpad_buttons[code] = button



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
	var frame := Color(0.29, 0.18, 0.10, 1)
	var wood := Color(0.48, 0.29, 0.15, 1)
	var wood_light := Color(0.52, 0.33, 0.18, 1)
	var seam := Color(0.37, 0.22, 0.11, 1)
	var panel_edge := Color(0.37, 0.22, 0.11, 1)
	img.fill(frame)
	_fill_rect(img, 14, 14, 242, 242, wood)
	# Vertical planks.
	for x in [56, 98, 140, 182]:
		_fill_rect(img, x, 14, x + 2, 242, seam)
	# Two recessed panels with a lighter face.
	for py0 in [30, 138]:
		_fill_rect(img, 34, py0, 222, py0 + 84, panel_edge)
		_fill_rect(img, 38, py0 + 4, 218, py0 + 80, wood_light)
	# Brass knob.
	var kx := 206
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
	return clamp(w / 1000.0, 1.15, 1.6)


func _scaled(base: int) -> int:
	return int(round(base * _font_scale()))


func _refresh_fonts() -> void:
	if hero_label == null:
		return
	hero_label.add_theme_font_size_override("font_size", _scaled(26))
	reset_button.add_theme_font_size_override("font_size", _scaled(22))
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
	var narrow := get_viewport_rect().size.x < NARROW_WIDTH
	if layout_init_done and narrow == layout_narrow:
		return
	layout_narrow = narrow
	layout_init_done = true
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
	else:
		if sidebar.get_parent() == vbox:
			vbox.remove_child(sidebar)
		if sidebar.get_parent() != game_row:
			game_row.add_child(sidebar)
		sidebar.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
		sidebar.size_flags_horizontal = SIZE_FILL
		sidebar.size_flags_vertical = SIZE_EXPAND_FILL
		sidebar.size_flags_stretch_ratio = 1.0
		game_row.size_flags_stretch_ratio = 1.0
	call_deferred("_apply_cell_size")


func _apply_cell_size() -> void:
	if scene_grid == null or scene_panel == null or scene_cols <= 0 or scene_rows <= 0:
		return
	var cell := FALLBACK_CELL
	var avail := scene_panel.size
	if avail.x > 0 and avail.y > 0:
		cell = int(min(avail.x / scene_cols, avail.y / scene_rows))
		cell = max(cell, MIN_CELL)
	for child in scene_grid.get_children():
		child.custom_minimum_size = Vector2(cell, cell)
	for entry in small_sprites:
		entry["node"].custom_minimum_size = Vector2(cell / 2, cell / 2)
	if fog_overlay == null:
		return
	# Fog overlay: one dark column per run, from the run's top fog cell
	# down to the scene panel's bottom edge, so the corridor descends
	# into darkness with no end in sight. The overlay is grid-sized and
	# centred like the grid; its children may extend past its bottom
	# edge — nothing in the chain clips them — which also covers the
	# panel's bottom gap in portrait windows.
	for child in fog_overlay.get_children():
		fog_overlay.remove_child(child)
		child.free()
	fog_overlay.visible = not fog_runs.is_empty() and not showing_photo
	if photo_rect != null and showing_photo:
		photo_rect.custom_minimum_size = Vector2(max(scene_panel.size.x - 8, 0), max(scene_panel.size.y - 8, 0))
	if fog_runs.is_empty():
		return
	var grid_h := scene_rows * cell
	var origin_y := (scene_panel.size.y - grid_h) / 2.0
	fog_overlay.custom_minimum_size = Vector2(scene_cols * cell, grid_h)
	for run in fog_runs:
		var rect := Panel.new()
		rect.mouse_filter = MOUSE_FILTER_IGNORE
		rect.add_theme_stylebox_override("panel", _panel_style(Color(0.2, 0.17, 0.26), Color(0, 0, 0, 0), 0))
		rect.position = Vector2(run["col"] * cell, run["row"] * cell)
		rect.size = Vector2(run["span"] * cell, scene_panel.size.y - (origin_y + run["row"] * cell))
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
		return _merged_style(ROAD_COLOR, up_same, down_same, left_same, right_same)
	if emoji == "🚪":
		# Flat frame colour behind the door texture child.
		return _panel_style(DOOR_BORDER, Color(0, 0, 0, 0), 0)
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

	# Scene tiles.
	for child in scene_grid.get_children():
		child.queue_free()
	animated_tiles = []
	small_sprites = []
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
			var same := func(nx: int, ny: int) -> bool:
				if ny < 0 or ny >= tiles.size() or nx < 0 or nx >= tiles[ny].size():
					return false
				return tiles[ny][nx] == emoji
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
			if not is_player and emoji == "🚪":
				var door := TextureRect.new()
				door.texture = _door_texture()
				door.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				door.stretch_mode = TextureRect.STRETCH_SCALE
				cell.add_child(door)
				continue
			if not is_player and emoji in ["🕳", "▫️", "✖️"]:
				continue
			if is_player:
				var frames := _sprite_frames(SPRITES.get(dlg_hero, "toshik"))
				if frames.size() > 0:
					var sprite := TextureRect.new()
					sprite.texture = frames[0]
					sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					cell.add_child(sprite)
					if frames.size() > 1:
						animated_tiles.append({"node": sprite, "frames": frames, "interval": 0.35, "elapsed": 0.0, "idx": 0})
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
						if sprite_name in ITEM_SPRITES:
							# Half-size, centered in its cell; the
							# exact size is fixed up in _apply_cell_size.
							var wrap := CenterContainer.new()
							sprite.custom_minimum_size = Vector2(FALLBACK_CELL / 2, FALLBACK_CELL / 2)
							wrap.add_child(sprite)
							cell.add_child(wrap)
							small_sprites.append({"node": sprite, "cell": cell})
						else:
							cell.add_child(sprite)
						if frames.size() > 1:
							var interval := 0.18 if sprite_name == "fire" else 0.35
							animated_tiles.append({"node": sprite, "frames": frames, "interval": interval, "elapsed": 0.0, "idx": 0})
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
			button.pressed.connect(_on_answer.bind(answer))
			answers_box.add_child(button)
	dpad_block.visible = has_move
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


func _on_reset() -> void:
	engine.new_game()
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
