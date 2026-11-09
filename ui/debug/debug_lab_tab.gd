class_name DebugLabTab extends DebugTab

###########################
## Вкладка «Lab»: корректор графики на чистом дефолте Godot (ATTN_14 §14.16)
###########################
## Не связана с вкладкой Graphics (та правит пресеты Look, Time, Quality). Здесь картинка не зависит от пресетов:
## «Включить» сбрасывает Environment, свет, камеру (без позиции и зума), Viewport и настройки RenderingServer к умолчаниям Godot.
## Дальше параметры правят где удобно: Remote в редакторе (Environment, свет, камера, Viewport) или строки RenderingServer ниже.
## «Записать» сравнивает текущие значения со слепком, снятым при сбросе, и пишет отличия в user://lab/<имя>.json.
## Птички (что включено поверх дефолта: SkyFill, FakeAO и т.д.) запоминаются в settings.cfg [lab] и применяются при каждом входе.
## Включается только в Observe (карточка Look → Lab делает то же самое).

var _lab: GfxLab

var _state: Label
var _enter_btn: Button
var _leave_btn: Button
var _flag_checks: Dictionary = {}   # id птички -> CheckBox
var _rs_rows: Array = []            # [{name, control}]
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
	_build_rs()
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
	_sync_rs()
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


## Настройки RenderingServer: в Remote их нет, правятся здесь (значения идут в слепок и в файл как цель rs)
func _build_rs() -> void:
	var fold := FoldableContainer.new()
	fold.title = "RenderingServer (тени, SSAO quality)"
	fold.folded = true
	var grid := GridContainer.new()
	grid.columns = 2
	fold.add_child(grid)
	add_child(fold)
	var defaults := GfxLab.RenderSettings.new()
	for k in GfxLab.RenderSettings.MAP:
		var key: String = k
		var label := Label.new()
		label.text = key.capitalize()
		grid.add_child(label)
		var v: Variant = defaults.get(key)
		var control: Control
		if typeof(v) == TYPE_BOOL:
			var cb := CheckBox.new()
			cb.size_flags_horizontal = Control.SIZE_SHRINK_END
			cb.toggled.connect(func(on: bool) -> void: _lab.rs_set(key, on))
			control = cb
		else:
			var spin := make_spin(0.0, 16384.0, 1.0 if typeof(v) == TYPE_INT else 0.01)
			var is_int := typeof(v) == TYPE_INT
			spin.value_changed.connect(func(x: float) -> void: _lab.rs_set(key, int(x) if is_int else x))
			control = spin
		grid.add_child(control)
		_rs_rows.append({"name": key, "control": control})


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


func _sync_rs() -> void:
	for r in _rs_rows:
		var v: Variant = _lab.rs_get(r.name)
		var c: Control = r.control
		if c is CheckBox:
			(c as CheckBox).disabled = v == null
			if v != null:
				(c as CheckBox).set_pressed_no_signal(bool(v))
		elif c is SpinBox:
			(c as SpinBox).editable = v != null
			if v != null:
				set_spin(c as SpinBox, float(v))


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
