class_name DebugLabTab extends DebugTab

###########################
## Вкладка «Lab»: корректор графики на чистом дефолте Godot (ATTN_14 §14.16)
###########################
## Не связана с вкладкой Graphics (та правит пресеты Look, Time, Quality). Здесь картинка не зависит от пресетов:
## «Включить» сбрасывает Environment, свет, камеру (без позиции и зума), Viewport и настройки RenderingServer к умолчаниям Godot.
## Дальше параметры правят где удобно: Remote в редакторе (Environment, свет, камера, Viewport) или список «Параметры» ниже (L3):
## он строится по свойствам целей (все типы: bool, int, enum, float, Vector2-4, Color, String), с поиском и фильтром «только изменённые».
## Там же настройки RenderingServer (в Remote их нет).
## «Записать» сравнивает текущие значения со слепком, снятым при сбросе, и пишет отличия в user://lab/<имя>.json.
## Птички (что включено поверх дефолта: SkyFill, FakeAO и т.д.) запоминаются в settings.cfg [lab] и применяются при каждом входе.
## Включается только в Observe (карточка Look → Lab делает то же самое).

var _lab: GfxLab

var _state: Label
var _enter_btn: Button
var _leave_btn: Button
var _flag_checks: Dictionary = {}   # id птички -> CheckBox
## Список параметров (L3)
var _search: LineEdit
var _only_changed: CheckBox
var _list_note: Label
var _list_box: VBoxContainer
var _sections: Array[Dictionary] = []   # [{target, fold, title, rows, groups: [{header, grid, rows}]}]
var _rows: Array[Dictionary] = []       # все строки: {target, prop, type, group, cells, label, controls, changed}
var _sig := ""                          # какие цели были при последней сборке списка
var _fold_state: Dictionary = {}        # цель -> свёрнута ли (запоминается между пересборками)
var _diff_title: Label
var _diff_text: Label
var _name_edit: LineEdit
var _note_edit: LineEdit
var _save_btn: Button
var _files: OptionButton
var _load_btn: Button
var _delete_btn: Button
var _project_btn: Button
var _status: Label
var _file_paths: Array[Dictionary] = []
var _last_diff_text := ""


func _init() -> void:
	name = &"Lab"
	_lab = GFX.lab
	if _lab == null:
		add_child(make_note("Lab недоступен: нет корректора графики (режим --fast или не debug)."))
		return
	add_child(make_note("Корректор на чистом дефолте Godot. Включается только в Observe. Не связан с вкладкой Graphics: пресеты Look, Time и Quality здесь не применяются."))
	_state = Label.new()
	add_child(_state)

	var row := HBoxContainer.new()
	add_child(row)
	_enter_btn = Button.new()
	_enter_btn.pressed.connect(_on_enter)
	row.add_child(_enter_btn)
	_leave_btn = Button.new()
	_leave_btn.text = "Выйти (вернуть игру)"
	_leave_btn.pressed.connect(_on_leave)
	row.add_child(_leave_btn)

	_build_flags()
	_build_params()
	_build_diff()
	_build_files()

	_status = make_note("")
	_status.hide()
	add_child(_status)

	_lab.state_changed.connect(_on_lab_state_changed)
	_lab.flags_changed.connect(_sync_flags)
	_refresh_files()


func opened() -> void:
	if _lab == null:
		return
	_refresh_files()
	refresh()


func refresh() -> void:
	if _lab == null:
		return
	var on := _lab.active
	_state.text = "Lab включён: правки не перезаписываются пресетами" if on else "Lab выключен: работает обычная графика"
	_state.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5) if on else Color(0.7, 0.7, 0.7))
	_enter_btn.text = "Сбросить заново (чистый дефолт)" if on else "Включить Lab (чистый дефолт)"
	_enter_btn.disabled = not on and not GFX.is_observe_active()
	_enter_btn.tooltip_text = "" if (on or GFX.is_observe_active()) else "Сначала войдите в режим Observe"
	_leave_btn.disabled = not on
	_sync_flags()
	_sync_params()
	_refresh_diff()
	_save_btn.disabled = not on
	var has_file := _files.item_count > 0 and _files.selected >= 0
	_load_btn.disabled = not on or not has_file
	_delete_btn.disabled = not has_file or _selected_file().get("project", false)
	_project_btn.disabled = not has_file or _selected_file().get("project", false) or not OS.has_feature("editor")


# --- построение ---

func _build_flags() -> void:
	add_child(make_header("— Включено поверх дефолта (запоминается) —"))
	for f in GfxLab.FLAGS:
		var cb := CheckBox.new()
		cb.text = f["title"]
		cb.tooltip_text = f["tip"]
		cb.toggled.connect(func(on: bool) -> void: _lab.set_flag(f["id"], on))
		add_child(cb)
		_flag_checks[f["id"]] = cb
	var reset := Button.new()
	reset.text = "Птички к дефолту (только солнце)"
	reset.pressed.connect(func() -> void: _lab.reset_flags())
	add_child(reset)


## Список параметров: поиск, фильтр и место под секции целей (строки строятся в _rebuild_params, когда Lab включён)
func _build_params() -> void:
	add_child(make_header("— Параметры (все цели Lab) —"))
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по имени или группе (ssao, fog, shadow...)"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _apply_filter(true))
	add_child(_search)
	_only_changed = CheckBox.new()
	_only_changed.text = "Только изменённые"
	_only_changed.toggled.connect(func(_on: bool) -> void: _apply_filter(true))
	add_child(_only_changed)
	_list_note = make_note("Включите Lab: список параметров появится здесь.")
	add_child(_list_note)
	_list_box = VBoxContainer.new()
	add_child(_list_box)


## Пересобрать секции целей. Зовётся, когда сменился состав целей (вход в Lab, сброс, птичка CameraAttributes, загрузка файла)
func _rebuild_params() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_sections.clear()
	_rows.clear()
	_sig = _lab.signature()
	_list_note.visible = _lab.target_ids().is_empty()
	for t in _lab.target_ids():
		_build_section(t)
	_apply_filter(false)


func _build_section(target: String) -> void:
	var fold := FoldableContainer.new()
	fold.title = String(GfxLab.TARGET_TITLES.get(target, target))
	fold.folded = bool(_fold_state.get(target, true))
	fold.folding_changed.connect(func(is_folded: bool) -> void:
		if not _filter_active():
			_fold_state[target] = is_folded)
	var box := VBoxContainer.new()
	fold.add_child(box)
	_list_box.add_child(fold)
	var sec := {"target": target, "fold": fold, "title": fold.title, "rows": [], "groups": []}
	var group_by_name := {}
	for info in _lab.describe(target):
		var gname := String(info.get("group", ""))
		var g: Dictionary
		if group_by_name.has(gname):
			g = group_by_name[gname]
		else:
			var header: Label = null
			if gname != "":
				header = make_header(gname.capitalize())
				box.add_child(header)
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override(&"h_separation", 6)
			box.add_child(grid)
			g = {"header": header, "grid": grid, "rows": []}
			group_by_name[gname] = g
			(sec["groups"] as Array).append(g)
		var row := _make_row(target, info, g["grid"])
		if row.is_empty():
			continue
		(g["rows"] as Array).append(row)
		(sec["rows"] as Array).append(row)
		_rows.append(row)
	_sections.append(sec)


## Строка параметра: подпись, элемент по типу, кнопка R (вернуть к дефолту). Пустой словарь: тип не поддержан
func _make_row(target: String, info: Dictionary, grid: GridContainer) -> Dictionary:
	var prop := String(info["name"])
	var type := int(info["type"])
	var hint := int(info.get("hint", 0))
	var hint_string := String(info.get("hint_string", ""))
	var label := Label.new()
	label.text = prop
	label.tooltip_text = "%s.%s" % [target, prop]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.custom_minimum_size.x = 120.0
	var controls: Array = []
	var control: Control
	match type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.size_flags_horizontal = Control.SIZE_SHRINK_END
			cb.toggled.connect(func(on: bool) -> void: _write(target, prop, on))
			controls.append(cb)
			control = cb
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.edit_alpha = hint != PROPERTY_HINT_COLOR_NO_ALPHA
			cp.custom_minimum_size = Vector2(110.0, 28.0)
			cp.size_flags_horizontal = Control.SIZE_SHRINK_END
			cp.color_changed.connect(func(c: Color) -> void: _write(target, prop, c))
			controls.append(cp)
			control = cp
		TYPE_STRING:
			var le := LineEdit.new()
			le.custom_minimum_size.x = 110.0
			le.text_submitted.connect(func(t: String) -> void: _write(target, prop, t))
			controls.append(le)
			control = le
		TYPE_INT, TYPE_FLOAT:
			if type == TYPE_INT and hint == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				ob.size_flags_horizontal = Control.SIZE_SHRINK_END
				var idx := 0
				for part in hint_string.split(","):
					var kv := part.split(":")
					var val := int(kv[1]) if kv.size() > 1 else idx
					ob.add_item(kv[0], val)
					idx = val + 1
				ob.item_selected.connect(func(i: int) -> void: _write(target, prop, ob.get_item_id(i)))
				controls.append(ob)
				control = ob
			else:
				var is_int := type == TYPE_INT
				var spin := _make_spin_for(is_int, hint, hint_string)
				spin.value_changed.connect(func(v: float) -> void: _write(target, prop, int(v) if is_int else v))
				controls.append(spin)
				control = spin
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			var n := 2 if type == TYPE_VECTOR2 else (3 if type == TYPE_VECTOR3 else 4)
			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_SHRINK_END
			for k in n:
				var spin := _make_spin_for(false, hint, hint_string)
				spin.custom_minimum_size.x = 70.0
				spin.value_changed.connect(func(_v: float) -> void: _write(target, prop, _vector_from(type, controls)))
				controls.append(spin)
				hb.add_child(spin)
			control = hb
		_:
			return {}
	var reset := Button.new()
	reset.text = "R"
	reset.flat = true
	reset.tooltip_text = "Вернуть к дефолту Godot (значение после сброса)"
	reset.pressed.connect(func() -> void:
		_lab.reset_value(target, prop)
		_sync_params())
	grid.add_child(label)
	grid.add_child(control)
	grid.add_child(reset)
	return {"target": target, "prop": prop, "type": type, "group": String(info.get("group", "")),
			"cells": [label, control, reset], "label": label, "controls": controls, "changed": false}


## SpinBox под int или float: границы и шаг из подсказки диапазона, иначе без границ. Вручную можно ввести любое значение
func _make_spin_for(is_int: bool, hint: int, hint_string: String) -> SpinBox:
	var lo := -100000.0
	var hi := 100000.0
	var step := 1.0 if is_int else 0.001
	if hint == PROPERTY_HINT_RANGE:
		var parts := hint_string.split(",")
		if parts.size() >= 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			lo = float(parts[0])
			hi = float(parts[1])
		if parts.size() >= 3 and parts[2].is_valid_float() and float(parts[2]) > 0.0:
			step = float(parts[2])
	var spin := make_spin(lo, hi, step)
	spin.allow_lesser = true
	return spin


static func _vector_from(type: int, spins: Array) -> Variant:
	match type:
		TYPE_VECTOR2:
			return Vector2((spins[0] as SpinBox).value, (spins[1] as SpinBox).value)
		TYPE_VECTOR3:
			return Vector3((spins[0] as SpinBox).value, (spins[1] as SpinBox).value, (spins[2] as SpinBox).value)
	return Vector4((spins[0] as SpinBox).value, (spins[1] as SpinBox).value, (spins[2] as SpinBox).value, (spins[3] as SpinBox).value)


func _write(target: String, prop: String, value: Variant) -> void:
	_lab.set_value(target, prop, value)


func _build_diff() -> void:
	add_child(make_header("— Отличия от дефолта —"))
	_diff_title = Label.new()
	add_child(_diff_title)
	_diff_text = make_note("")
	add_child(_diff_text)


func _build_files() -> void:
	add_child(make_header("— Файлы экспериментов —"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Имя файла (пусто: lab_дата_время)"
	add_child(_name_edit)
	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = "Заметка (что пробовал)"
	add_child(_note_edit)
	_save_btn = Button.new()
	_save_btn.text = "Записать отличия"
	_save_btn.pressed.connect(_on_save)
	add_child(_save_btn)
	_files = OptionButton.new()
	_files.item_selected.connect(func(_i: int) -> void: refresh())
	add_child(_files)
	var row := HBoxContainer.new()
	add_child(row)
	_load_btn = Button.new()
	_load_btn.text = "Загрузить"
	_load_btn.tooltip_text = "Чистый дефолт, затем птички и значения из файла"
	_load_btn.pressed.connect(_on_load)
	row.add_child(_load_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "Удалить"
	_delete_btn.pressed.connect(_on_delete)
	row.add_child(_delete_btn)
	_project_btn = Button.new()
	_project_btn.text = "В проект"
	_project_btn.tooltip_text = "Копия в res://data/graphics/lab/ (только запуск из редактора), её надо закоммитить"
	_project_btn.pressed.connect(_on_to_project)
	row.add_child(_project_btn)


# --- состояние ---

func _on_lab_state_changed() -> void:
	refresh()


func _sync_flags() -> void:
	for id in _flag_checks:
		(_flag_checks[id] as CheckBox).set_pressed_no_signal(_lab.get_flag(id))


## Значения строк из текущих свойств целей (правка в Remote видна здесь), подсветка изменённых, счётчики секций
func _sync_params() -> void:
	if not _lab.active:
		if not _sections.is_empty():
			_rebuild_params()
		return
	if _lab.signature() != _sig:
		_rebuild_params()
	var any_flip := false
	for row in _rows:
		var cur: Variant = _lab.get_value(row.target, row.prop)
		_read_row(row, cur)
		var changed := not GfxLab.values_equal(_lab.base_value(row.target, row.prop), cur)
		if changed != row.changed:
			row.changed = changed
			any_flip = true
			var lbl := row.label as Label
			if changed:
				lbl.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3))
			else:
				lbl.remove_theme_color_override(&"font_color")
	for sec in _sections:
		var n := 0
		for row in sec.rows:
			if row.changed:
				n += 1
		var title := "%s (%d)" % [sec.title, (sec.rows as Array).size()]
		if n > 0:
			title += ", изменено %d" % n
		if (sec.fold as FoldableContainer).title != title:
			(sec.fold as FoldableContainer).title = title
	if any_flip and _only_changed.button_pressed:
		_apply_filter(false)


func _read_row(row: Dictionary, v: Variant) -> void:
	if v == null:
		return
	var ctl: Array = row.controls
	match int(row.type):
		TYPE_BOOL:
			(ctl[0] as CheckBox).set_pressed_no_signal(bool(v))
		TYPE_COLOR:
			var cp := ctl[0] as ColorPickerButton
			if not cp.color.is_equal_approx(v):
				cp.color = v
		TYPE_STRING:
			var le := ctl[0] as LineEdit
			if not le.has_focus() and le.text != String(v):
				le.text = String(v)
		TYPE_INT, TYPE_FLOAT:
			if ctl[0] is OptionButton:
				var ob := ctl[0] as OptionButton
				var i := ob.get_item_index(int(v))
				if i >= 0:
					ob.select(i)
			else:
				set_spin(ctl[0] as SpinBox, float(v))
		TYPE_VECTOR2:
			var a: Vector2 = v
			set_spin(ctl[0], a.x)
			set_spin(ctl[1], a.y)
		TYPE_VECTOR3:
			var b: Vector3 = v
			set_spin(ctl[0], b.x)
			set_spin(ctl[1], b.y)
			set_spin(ctl[2], b.z)
		TYPE_VECTOR4:
			var c4: Vector4 = v
			set_spin(ctl[0], c4.x)
			set_spin(ctl[1], c4.y)
			set_spin(ctl[2], c4.z)
			set_spin(ctl[3], c4.w)


func _filter_active() -> bool:
	return _search != null and (not _search.text.strip_edges().is_empty() or _only_changed.button_pressed)


## Скрыть строки, не подходящие под поиск и фильтр. unfold = true (меняли поиск или галочку): секции с совпадениями раскрываются,
## без фильтра секции возвращаются в запомненное состояние
func _apply_filter(unfold: bool) -> void:
	var q := _search.text.strip_edges().to_lower().replace(" ", "_")
	var only := _only_changed.button_pressed
	var active := _filter_active()
	for sec in _sections:
		var sec_any := false
		for g in sec.groups:
			var g_any := false
			for row in g.rows:
				var matches := true
				if only and not row.changed:
					matches = false
				if matches and q != "":
					matches = String(row.prop).contains(q) or String(row.group).to_lower().contains(q) \
							or String(row.target).contains(q)
				for cell in row.cells:
					(cell as Control).visible = matches
				g_any = g_any or matches
			(g.grid as Control).visible = g_any
			if g.header != null:
				(g.header as Control).visible = g_any
			sec_any = sec_any or g_any
		(sec.fold as Control).visible = sec_any or not active
		if unfold:
			if active:
				(sec.fold as FoldableContainer).folded = not sec_any
			else:
				(sec.fold as FoldableContainer).folded = bool(_fold_state.get(sec.target, true))


func _refresh_diff() -> void:
	var n := _lab.changed_count()
	_diff_title.text = "Изменено параметров: %d" % n
	var text := _lab.changes_text() if n > 0 else "(без отличий)"
	if text != _last_diff_text:
		_last_diff_text = text
		_diff_text.text = text


func _refresh_files() -> void:
	var prev := String(_selected_file().get("path", ""))
	_files.clear()
	_file_paths = _lab.list_files()
	var select := 0
	for i in _file_paths.size():
		_files.add_item(_file_paths[i]["title"])
		if _file_paths[i]["path"] == prev:
			select = i
	if _file_paths.is_empty():
		_files.add_item("(файлов нет)")
		_files.disabled = true
	else:
		_files.disabled = false
		_files.select(select)


func _selected_file() -> Dictionary:
	if _files == null or _file_paths.is_empty() or _files.selected < 0 or _files.selected >= _file_paths.size():
		return {}
	return _file_paths[_files.selected]


# --- действия ---

func _on_enter() -> void:
	if _lab.active:
		_lab.rebuild()
		_say("Сброшено к чистому дефолту. Правки потеряны.", true)
	elif GFX.enter_lab():
		_say("Lab включён. Правьте параметры в Remote или здесь, затем «Записать отличия».", true)
	else:
		_say("Lab не включился: нужен режим Observe.", false)
	refresh()


func _on_leave() -> void:
	GFX.exit_lab()
	_say("Lab выключен, игра вернулась к Look, Time и Quality.", true)
	refresh()


func _on_save() -> void:
	var path := _lab.save_file(_name_edit.text, _note_edit.text)
	if path == "":
		_say(_lab.last_error, false)
		return
	_say("Записан " + path, true)
	_refresh_files()
	for i in _file_paths.size():
		if _file_paths[i]["path"] == path:
			_files.select(i)
	refresh()


func _on_load() -> void:
	var f := _selected_file()
	if f.is_empty():
		return
	if not _lab.load_file(f["path"]):
		_say(_lab.last_error, false)
		return
	var msg := "Загружен " + String(f["path"])
	if not _lab.last_warnings.is_empty():
		msg += "\nПропущено:\n" + "\n".join(_lab.last_warnings)
	_say(msg, _lab.last_warnings.is_empty())
	refresh()


func _on_delete() -> void:
	var f := _selected_file()
	if f.is_empty():
		return
	if _lab.delete_file(f["path"]):
		_say("Удалён " + String(f["path"]), true)
	else:
		_say(_lab.last_error, false)
	_refresh_files()
	refresh()


func _on_to_project() -> void:
	var f := _selected_file()
	if f.is_empty():
		return
	var dst := _lab.copy_to_project(f["path"])
	if dst == "":
		_say(_lab.last_error, false)
		return
	_say("Скопирован в %s. Файл надо закоммитить." % dst, true)
	_refresh_files()
	refresh()


func _say(text: String, ok: bool) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.5, 0.4))
	_status.show()
