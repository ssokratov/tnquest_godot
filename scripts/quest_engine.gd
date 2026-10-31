class_name QuestEngine
extends RefCounted
## Faithful port of the tn2019quest Telegram bot engine (Bot/Logic/QuestService.cs).
##
## Original semantics, preserved in order:
##  1. An answer applies ChangeInventory, then ChangeJournal,
##     then MoveToDialog, then ChangeMap, then MoveToPos.
##  2. MoveToPos: if the destination cell has a dialog bound to its map icon,
##     that dialog opens; the position only changes if that dialog does not
##     have PreventMove (walls, fear, flames, police, road).
##  3. The visible map is a 3x3 window, or 5x5 once the player has the monocle
##     (Glasses), with the current hero's icon in the centre.
## Deliberately dropped: the Telegram turn restriction (ForPlayer) — this is a
## single-player game, and the story itself switches heroes at ZagsEnd.

const SAVE_PATH := "user://tn2019quest_save.json"

var data: Dictionary = {}
var map_rows: Array = []
var initial_map_rows: Array = []
var pos := Vector2i.ZERO
var inventory: Array = []
var journal_all: Array = []
var journal_finished: Array = []
var open_dialog := ""


func load_data(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "quest.json not found: " + path)
	data = JSON.parse_string(file.get_buffer(file.get_length()).get_string_from_utf8())
	initial_map_rows = (data["map_rows"] as Array).duplicate()


func new_game() -> void:
	map_rows = initial_map_rows.duplicate()
	pos = Vector2i(data["start_pos_toshik"][0], data["start_pos_toshik"][1])
	_set_cell(pos, "-")  # QuestService constructor clears the starting cell.
	inventory = []
	journal_all = (data["starting_journal"] as Array).duplicate()
	journal_finished = []
	open_dialog = data["start_dialog"]


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_save() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var save: Dictionary = JSON.parse_string(file.get_buffer(file.get_length()).get_string_from_utf8())
	if not (save.get("open_dialog", "") in (data["dialogs"] as Dictionary)):
		return false
	map_rows = (save["map_rows"] as Array).duplicate()
	pos = Vector2i(save["pos"][0], save["pos"][1])
	inventory = (save["inventory"] as Array).duplicate()
	journal_all = (save["journal_all"] as Array).duplicate()
	journal_finished = (save["journal_finished"] as Array).duplicate()
	open_dialog = save["open_dialog"]
	return true


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"pos": [pos.x, pos.y],
		"map_rows": map_rows,
		"inventory": inventory,
		"journal_all": journal_all,
		"journal_finished": journal_finished,
		"open_dialog": open_dialog,
	}))


func current_dialog() -> Dictionary:
	return (data["dialogs"] as Dictionary)[open_dialog]


func hero_name() -> String:
	return "Тошик" if current_dialog().get("story", "") == "toshik" else "Настя"


func current_message() -> String:
	var dlg := current_dialog()
	if dlg.get("dynamic", false):
		return _dynamic_message(dlg["name"])
	return dlg.get("message", "")


func available_answers() -> Array:
	var out: Array = []
	for answer in current_dialog().get("answers", []):
		if answer.get("hidden", false):
			continue
		if "available" in answer and not _eval_cond(answer["available"]):
			continue
		out.append(answer)
	return out


func apply_answer(answer: Dictionary) -> void:
	if "change_inventory" in answer:
		for step in (answer["change_inventory"] as Dictionary)["seq"]:
			if step["op"] == "Give":
				if step["item"] not in inventory:
					inventory.append(step["item"])
			elif step["op"] == "Take":
				inventory.erase(step["item"])
	if "change_journal" in answer:
		for step in (answer["change_journal"] as Dictionary)["seq"]:
			if step["op"] == "Open":
				if step["quest"] not in journal_all:
					journal_all.append(step["quest"])
			elif step["op"] == "Finish":
				if step["quest"] not in journal_all:
					journal_all.append(step["quest"])
				if step["quest"] not in journal_finished:
					journal_finished.append(step["quest"])
	if "move_to_dialog" in answer:
		open_dialog = answer["move_to_dialog"]
	if "change_map" in answer:
		for op in (answer["change_map"] as Dictionary)["map_ops"]:
			_apply_map_op(op)
	if "move_to_pos" in answer:
		_move_to(_eval_pos(answer["move_to_pos"]))


func visible_tiles() -> Array:
	# Returns rows of emoji strings, hero icon in the centre.
	var radius := 2 if "Glasses" in inventory else 1
	var dlg := current_dialog()
	var hero_emoji: String = _emoji(dlg.get("player_icon", "O"))
	var rows: Array = []
	for dy in range(-radius, radius + 1):
		var row: Array = []
		for dx in range(-radius, radius + 1):
			var cell := Vector2i(pos.x + dx, pos.y + dy)
			if cell == pos:
				row.append(hero_emoji)
			elif not _in_bounds(cell):
				row.append(_emoji("#"))
			else:
				row.append(_emoji(_cell(cell)))
		rows.append(row)
	return rows


# --- internals ---------------------------------------------------------------

func _eval_cond(cond: Dictionary) -> bool:
	if "check" in cond:
		match cond["check"]:
			"Has":
				return cond["name"] in inventory
			"IsOpen":
				return cond["name"] in journal_all and cond["name"] not in journal_finished
			"IsFinished":
				return cond["name"] in journal_finished
			"IsKnown":
				return cond["name"] in journal_all
		return false
	match cond.get("cond", ""):
		"and":
			return _eval_cond(cond["a"]) and _eval_cond(cond["b"])
		"or":
			return _eval_cond(cond["a"]) or _eval_cond(cond["b"])
		"not":
			return not _eval_cond(cond["a"])
	return true


func _eval_pos(expr: Dictionary) -> Vector2i:
	if expr.get("pos", false):
		return pos
	if expr.get("start", false):
		# Nastya's startPosition: the initial position of her icon.
		return Vector2i(data["start_pos_nastya"][0], data["start_pos_nastya"][1])
	if "icon" in expr:
		return _find_first(expr["icon"], map_rows)
	if "initial_icon" in expr:
		var icon = expr["initial_icon"]
		if icon is Dictionary:
			icon = icon["icon"]
		return _find_first(icon, initial_map_rows)
	if "move" in expr:
		var base := _eval_pos(expr["of"])
		match expr["move"]:
			"up": return Vector2i(base.x, base.y - 1)
			"down": return Vector2i(base.x, base.y + 1)
			"left": return Vector2i(base.x - 1, base.y)
			"right": return Vector2i(base.x + 1, base.y)
	if "arith" in expr:
		var base := _eval_pos(expr["a"])
		var n: int = expr["b"]["int"]
		if expr["arith"] == "add":
			return Vector2i(base.x + n, base.y)
		return Vector2i(base.x - n, base.y)
	return pos


func _move_to(target: Vector2i) -> void:
	if not _in_bounds(target):
		return
	var ch := _cell(target)
	var by_icon := _map_icon_dialogs()
	if ch in by_icon:
		open_dialog = by_icon[ch]
	var dlg := current_dialog()
	if not dlg.get("prevent_move", false):
		pos = target


func _apply_map_op(op: Dictionary) -> void:
	match op["op"]:
		"clear":
			_set_cell(_eval_pos(op["at"]), "-")
		"replace_first":
			var cell := _find_first(op["icon"], map_rows)
			_set_cell(cell, op["char"])
		"replace_at":
			_set_cell(_eval_pos(op["at"]), op["char"])


func _map_icon_dialogs() -> Dictionary:
	var out := {}
	for name in (data["dialogs"] as Dictionary):
		var dlg: Dictionary = data["dialogs"][name]
		if "map_icon" in dlg:
			out[dlg["map_icon"]] = name
	return out


func _find_first(icon: String, rows: Array) -> Vector2i:
	for y in rows.size():
		var row: String = rows[y]
		var x := row.find(icon)
		if x >= 0:
			return Vector2i(x, y)
	return pos


func _in_bounds(cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < map_rows.size() and cell.x >= 0 and cell.x < (map_rows[cell.y] as String).length()


func _cell(cell: Vector2i) -> String:
	return (map_rows[cell.y] as String)[cell.x]


func _set_cell(cell: Vector2i, ch: String) -> void:
	if not _in_bounds(cell):
		return
	var row: String = map_rows[cell.y]
	map_rows[cell.y] = row.substr(0, cell.x) + ch + row.substr(cell.x + 1)


func _emoji(icon: String) -> String:
	var table: Dictionary = data["emoji"]
	return table.get(icon, icon)


func _dynamic_message(name: String) -> String:
	match name:
		"InventoryToshik":
			var text := "*Инвентарь*:\n"
			if "Phone" in inventory: text += "📱 телефон\n"
			if "Project" in inventory: text += "📄 проект\n"
			if "Stick" in inventory: text += "⚡️ жезл\n"
			if "KolyanDachaKey" in inventory: text += "🔑 ключ\n"
			if "FireExtinguisher" in inventory: text += "🧯 огнетушитель\n"
			if "Glasses" in inventory: text += "🧐 монокль\n"
			if "Boots" in inventory: text += "👢 сапоги\n"
			if "Hat" in inventory: text += "🎩 шляпа\n"
			return text
		"InventoryNastya":
			var text := "*Инвентарь*:\n"
			if "Beer" in inventory: text += "🍻 два пива\n"
			return text
		"JournalToshik":
			return "*Журнал*:\n" + _quest_line("EnterHall", "Войти в зал") \
				+ _quest_line("AskForWedding", "Поговорить с работником ЗАГСа") \
				+ _quest_line("Demianov", "Позвонить Демьянову") \
				+ _quest_line("Jacob", "Замутить Якову телефон") \
				+ _quest_line("Sedosh", "Обсчитать проект капитанской хижины") \
				+ _quest_line("Kolyan", "Код КРАКОВ!") \
				+ _quest_line("KolyanDachaOpenDoor", "Открыть дверь дачного домика") \
				+ _quest_line("FireAlarm", "Потушить пожар") \
				+ _quest_line("Sokrat", "Починить Сократу роутер") \
				+ _quest_line("DressForWedding", "Приодеться к свадьбе")
		"JournalNastya":
			return "*Журнал*:\n" + _quest_line("Police", "Обойти полицейского") \
				+ _quest_line("BuyBeer", "Купить пива") \
				+ _quest_line("OrderTaxi", "Заказать такси") \
				+ _quest_line("FindCredits", "Достать 20 кредитов")
	return ""


func _quest_line(quest: String, text: String) -> String:
	if quest not in journal_all:
		return ""
	var mark := "✔️" if quest in journal_finished else "✖️"
	return mark + " " + text + "\n"
