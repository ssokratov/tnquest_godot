extends Control
## UI for the tn2019quest Godot port, indie-quest style.
##
## Layout, top to bottom:
##   header (hero + restart) | scene panel (tile map) | dialog box |
##   action chips + D-pad | hint.
## Dialog photos are NOT a separate element below the text: they open as a
## modal card over the scene (dimmed background, image + text + answers
## inside the card), so the photo intercepts control until you answer.
##
## Map tiles are drawn as panels (coloured by tile type) with a sprite or
## an emoji inside. Sprite tiles animate: characters cycle 3 frames,
## fire cycles faster. Game logic lives in quest_engine.gd; progress is
## saved automatically after every answer (user://tn2019quest_save.json).
## Controls: click an answer, or arrows / WASD for movement answers.

const QuestEngineScript := preload("res://scripts/quest_engine.gd")
var engine := QuestEngineScript.new()

var hero_label: Label
var scene_grid: GridContainer
var dialog_panel: PanelContainer
var dialog_label: RichTextLabel
var actions_box: FlowContainer
var dpad_panel: PanelContainer
var dpad_buttons := {}
var hint_label: Label
var modal: Control
var modal_image: TextureRect
var modal_text: RichTextLabel
var modal_answers: VBoxContainer
var bottom_box: VBoxContainer

var animated_tiles: Array = []
var anim_time := 0.0

const TILE_SIZE := 64
const MOVE_LABELS := {
	"t": "⬆️", "d": "⬇️", "l": "⬅️", "r": "➡️",
	"i": "💼", "j": "📖",
}
const MOVE_WORDS := {
	"t": "⬆️ Вверх", "d": "⬇️ Вниз", "l": "⬅️ Влево", "r": "➡️ Вправо",
	"i": "💼 Инвентарь", "j": "📖 Журнал",
}
const MOVE_KEYS := {
	KEY_UP: "t", KEY_W: "t",
	KEY_DOWN: "d", KEY_S: "d",
	KEY_LEFT: "l", KEY_A: "l",
	KEY_RIGHT: "r", KEY_D: "r",
}
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


func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	hero_label = Label.new()
	hero_label.size_flags_horizontal = SIZE_EXPAND_FILL
	hero_label.add_theme_font_size_override("font_size", 22)
	header.add_child(hero_label)
	var reset := Button.new()
	reset.text = "↻ Начать заново"
	reset.focus_mode = FOCUS_NONE
	reset.pressed.connect(_on_reset)
	header.add_child(reset)
	vbox.add_child(header)

	# Scene panel.
	var scene_panel := PanelContainer.new()
	scene_panel.size_flags_vertical = SIZE_EXPAND_FILL
	scene_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.11, 0.11, 0.16), Color(0.25, 0.25, 0.35)))
	vbox.add_child(scene_panel)
	var scene_center := CenterContainer.new()
	scene_panel.add_child(scene_center)
	scene_grid = GridContainer.new()
	# No gaps: walls and roads merge into continuous shapes; the floor
	# is the scene panel's own background, not a tile at all.
	scene_grid.add_theme_constant_override("h_separation", 0)
	scene_grid.add_theme_constant_override("v_separation", 0)
	scene_center.add_child(scene_grid)

	# Bottom area (hidden while a photo modal is open).
	bottom_box = VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom_box)

	dialog_panel = PanelContainer.new()
	dialog_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.14, 0.14, 0.22), Color(0.35, 0.35, 0.5)))
	bottom_box.add_child(dialog_panel)
	var dialog_margin := MarginContainer.new()
	dialog_margin.add_theme_constant_override("margin_left", 14)
	dialog_margin.add_theme_constant_override("margin_right", 14)
	dialog_margin.add_theme_constant_override("margin_top", 10)
	dialog_margin.add_theme_constant_override("margin_bottom", 10)
	dialog_panel.add_child(dialog_margin)
	dialog_label = RichTextLabel.new()
	dialog_label.bbcode_enabled = true
	_set_fit_content(dialog_label)
	dialog_label.add_theme_font_size_override("normal_font_size", 19)
	dialog_margin.add_child(dialog_label)

	# Actions (text answers) + D-pad row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bottom_box.add_child(row)
	actions_box = FlowContainer.new()
	actions_box.size_flags_horizontal = SIZE_EXPAND_FILL
	actions_box.add_theme_constant_override("h_separation", 8)
	actions_box.add_theme_constant_override("v_separation", 8)
	row.add_child(actions_box)

	dpad_panel = PanelContainer.new()
	dpad_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.14, 0.14, 0.22), Color(0.3, 0.3, 0.45), 10))
	row.add_child(dpad_panel)
	var dpad := GridContainer.new()
	dpad.columns = 3
	dpad.add_theme_constant_override("h_separation", 4)
	dpad.add_theme_constant_override("v_separation", 4)
	dpad_panel.add_child(dpad)
	# Row 1: inventory / up / journal; row 2: left / centre / right;
	# row 3: (empty) / down / (empty).
	var dpad_layout := ["i", "t", "j", "l", "", "r", "", "d", ""]
	for code in dpad_layout:
		if code == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(52, 52)
			dpad.add_child(spacer)
		else:
			var button := Button.new()
			button.text = MOVE_LABELS[code]
			button.custom_minimum_size = Vector2(52, 52)
			button.focus_mode = FOCUS_NONE
			button.add_theme_font_size_override("font_size", 22)
			button.pressed.connect(_on_move.bind(code))
			dpad.add_child(button)
			dpad_buttons[code] = button

	hint_label = Label.new()
	hint_label.text = "Стрелки / WASD — движение, когда оно предлагается. Прогресс сохраняется автоматически."
	hint_label.add_theme_font_size_override("font_size", 13)
	bottom_box.add_child(hint_label)

	_build_modal()


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


func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_preset(PRESET_FULL_RECT)
	modal.mouse_filter = MOUSE_FILTER_STOP
	modal.visible = false
	add_child(modal)
	var dim := ColorRect.new()
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.68)
	modal.add_child(dim)
	# The card fills almost the whole window (28 px margins): the photo
	# then takes every pixel the text and answers leave it.
	var modal_margin := MarginContainer.new()
	modal_margin.set_anchors_preset(PRESET_FULL_RECT)
	modal_margin.add_theme_constant_override("margin_left", 28)
	modal_margin.add_theme_constant_override("margin_right", 28)
	modal_margin.add_theme_constant_override("margin_top", 28)
	modal_margin.add_theme_constant_override("margin_bottom", 28)
	modal.add_child(modal_margin)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.15, 0.15, 0.24), Color(0.45, 0.45, 0.6)))
	modal_margin.add_child(card)
	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 16)
	card_margin.add_theme_constant_override("margin_right", 16)
	card_margin.add_theme_constant_override("margin_top", 14)
	card_margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(card_margin)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 12)
	card_margin.add_child(card_box)
	modal_image = TextureRect.new()
	modal_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	modal_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	modal_image.size_flags_horizontal = SIZE_EXPAND_FILL
	modal_image.size_flags_vertical = SIZE_EXPAND_FILL
	modal_image.custom_minimum_size = Vector2(0, 200)
	card_box.add_child(modal_image)
	modal_text = RichTextLabel.new()
	modal_text.bbcode_enabled = true
	_set_fit_content(modal_text)
	modal_text.add_theme_font_size_override("normal_font_size", 19)
	card_box.add_child(modal_text)
	modal_answers = VBoxContainer.new()
	modal_answers.add_theme_constant_override("separation", 8)
	card_box.add_child(modal_answers)


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
	# Wall/road share one emoji each, which is all merging needs.
	if is_player:
		# Soft round glow behind the hero, not a square frame.
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(1, 0.85, 0.2, 0.16)
		glow.corner_radius_top_left = 32
		glow.corner_radius_top_right = 32
		glow.corner_radius_bottom_left = 32
		glow.corner_radius_bottom_right = 32
		return glow
	if emoji == "⬛️":
		return _merged_style(Color(0.29, 0.29, 0.4), up_same, down_same, left_same, right_same)
	if emoji == "🕳":
		return _merged_style(Color(0.24, 0.24, 0.33), up_same, down_same, left_same, right_same)
	# Everything else (floor, characters, items, doors) sits directly on
	# the scene panel's background: no tile, no frame.
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
	var message := _markdown_to_bbcode(engine.current_message())
	var answers := engine.available_answers()
	var has_photo := "photo" in dlg

	# Scene tiles.
	for child in scene_grid.get_children():
		child.queue_free()
	animated_tiles = []
	var tiles: Array = engine.visible_tiles()
	scene_grid.columns = tiles[0].size()
	var centre := tiles.size() / 2
	var dlg_hero: String = dlg.get("player_icon", "O")
	for y in tiles.size():
		for x in tiles[y].size():
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			var is_player: bool = x == centre and y == centre
			var emoji: String = tiles[y][x]
			var same := func(nx: int, ny: int) -> bool:
				if ny < 0 or ny >= tiles.size() or nx < 0 or nx >= tiles[ny].size():
					return false
				return tiles[ny][nx] == emoji
			cell.add_theme_stylebox_override("panel", _cell_style(
				emoji, is_player,
				same.call(x, y - 1), same.call(x, y + 1),
				same.call(x - 1, y), same.call(x + 1, y)))
			scene_grid.add_child(cell)
			# Walls, roads and bare floor are pure background shapes:
			# nothing is drawn inside them.
			if not is_player and emoji in ["⬛️", "🕳", "▫️"]:
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
						cell.add_child(sprite)
						if frames.size() > 1:
							var interval := 0.18 if sprite_name == "fire" else 0.35
							animated_tiles.append({"node": sprite, "frames": frames, "interval": interval, "elapsed": 0.0, "idx": 0})
					else:
						_add_emoji_cell(cell, tiles[y][x])
				else:
					_add_emoji_cell(cell, tiles[y][x])

	# Bottom UI vs photo modal.
	if has_photo:
		bottom_box.visible = false
		# No size cap here any more: the TextureRect expands to fill the
		# card (minus text and answers) and scales the photo up or down
		# to fit, keeping its aspect ratio.
		modal_image.texture = load("res://assets/" + dlg["photo"]) as Texture2D
		modal_text.text = message
		for child in modal_answers.get_children():
			child.queue_free()
		for answer in answers:
			var button := Button.new()
			button.text = _answer_label(answer["message"])
			button.focus_mode = FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_font_size_override("font_size", 18)
			button.pressed.connect(_on_answer.bind(answer))
			modal_answers.add_child(button)
		modal.visible = true
	else:
		modal.visible = false
		bottom_box.visible = true
		dialog_label.text = message
		for child in actions_box.get_children():
			child.queue_free()
		var has_move := false
		for answer in answers:
			if answer["message"] in MOVE_LABELS:
				has_move = true
			else:
				var button := Button.new()
				button.text = _answer_label(answer["message"])
				button.focus_mode = FOCUS_NONE
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.add_theme_font_size_override("font_size", 17)
				button.pressed.connect(_on_answer.bind(answer))
				actions_box.add_child(button)
		dpad_panel.visible = has_move
		for code in dpad_buttons:
			var found := false
			for answer in answers:
				if answer["message"] == code:
					found = true
					break
			var button: Button = dpad_buttons[code]
			button.disabled = not found
			button.modulate = Color(1, 1, 1, 1) if found else Color(1, 1, 1, 0.35)


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
	return message.replace("*", "").replace("_", "")


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
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
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
