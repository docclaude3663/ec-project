class_name DebugGraphicsTab extends DebugTab

###########################
## Вкладка «Graphics»: правка активных Look, Time и Quality на лету
###########################
## Строки строятся по свойствам ресурсов пресетов (GraphicsPreset, TimeOfDayPreset, QualityPreset): новое поле
## с @export появляется здесь само, группы = @export_category. Значение пишется прямо в пресет, картинка
## пересчитывается (GFX.reapply). Смена Look, Time или Quality карточками Observe перестраивает вкладку.
## «R» у строки и «Вернуть все» возвращают значения на момент первого показа пресета в этой сессии.
## «В пресеты» записывает изменённые пресеты в .tres (res://data/graphics/...): они переопределяют встроенные
## по id и попадают в коммит. «Копировать» кладёт отличия в буфер текстом «поле = значение».
## Свет в нодах сцены (SkyFill, лампа: bias, дальность теней) здесь не правится: это константы EnvironmentRoot.

const SETTINGS_SECTION := "debug"
const CLOSED_KEY := "closed_graphics"
const KINDS := [
	{"kind": "look", "title": "Look", "dir": "res://data/graphics/looks/"},
	{"kind": "time", "title": "Time", "dir": "res://data/graphics/time/"},
	{"kind": "quality", "title": "Quality", "dir": "res://data/graphics/quality/"},
]

## Активные ресурсы: kind -> Resource
var _active: Dictionary = {}
## Значения на момент первого показа: Resource -> {поле: значение}
var _bases: Dictionary = {}
## Resource -> {kind, dir}
var _meta: Dictionary = {}
## Строки текущего построения: Array[{res, name, type, control}]
var _rows: Array = []
var _closed: Array = []
var _closed_loaded := false

var _title: Label
var _body: VBoxContainer
var _passport_btn: Button
var _copy_btn: Button
var _status: Label
var _confirm: ConfirmationDialog


func _init() -> void:
	name = &"Graphics"
	_title = Label.new()
	_title.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5))
	add_child(_title)
	add_child(make_note("Правка активных Look, Time и Quality на лету. Файл не меняется, пока не нажмете «В пресеты»."))

	var reset_all := Button.new()
	reset_all.text = "Вернуть все (как при открытии)"
	reset_all.pressed.connect(_reset_all)
	add_child(reset_all)

	var row := HBoxContainer.new()
	add_child(row)
	_passport_btn = Button.new()
	_passport_btn.text = "В пресеты..."
	_passport_btn.pressed.connect(_ask_save)
	row.add_child(_passport_btn)
	_copy_btn = Button.new()
	_copy_btn.text = "Копировать"
	_copy_btn.tooltip_text = "Скопировать отличия текстом «поле = значение»"
	_copy_btn.pressed.connect(_copy_diff)
	row.add_child(_copy_btn)
	_status = make_note("")
	_status.hide()
	add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "В пресеты"
	_confirm.ok_button_text = "Записать"
	_confirm.dialog_autowrap = true
	_confirm.confirmed.connect(_write_presets)
	add_child(_confirm)

	_body = VBoxContainer.new()
	add_child(_body)


func opened() -> void:
	_rebuild_if_needed()
	refresh()


func refresh() -> void:
	_rebuild_if_needed()
	for r in _rows:
		_read_row(r)
	_update_buttons()


## Перестраивает строки, если активный Look, Time или Quality сменился
func _rebuild_if_needed() -> void:
	var cur := {
		"look": GFX.looks.get(GFX.state.look),
		"time": GFX.times.get(GFX.state.time),
		"quality": GFX.qualities.get(GFX.state.quality),
	}
	var same := not _rows.is_empty()
	for k in cur:
		if _active.get(k) != cur[k]:
			same = false
	if same:
		return
	_active = cur
	_build()


func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_rows.clear()
	if not _closed_loaded:
		_closed_loaded = true
		var saved: Variant = Settings.get_value(SETTINGS_SECTION, CLOSED_KEY, null)
		_closed = saved if saved is Array else []
		if saved == null:
			_closed = _default_closed()
	var names := PackedStringArray()
	for k in KINDS:
		var res: Resource = _active.get(k.kind)
		if res == null:
			continue
		names.append("%s: %s" % [k.title, res.get("id")])
		if not _bases.has(res):
			_bases[res] = _snapshot(res)
			_meta[res] = {"kind": k.kind, "dir": k.dir, "title": k.title}
		_body.add_child(make_header("— %s: %s —" % [k.title, res.get("id")]))
		_build_groups(res, k)
	_title.text = "  ·  ".join(names)


## Все группы свернуты, кроме первой группы Look
func _default_closed() -> Array:
	var out: Array = []
	var first := true
	for k in KINDS:
		var res: Resource = _active.get(k.kind)
		if res == null:
			continue
		for cat in _categories(res):
			if not first:
				out.append(k.kind + ":" + cat)
			first = false
	return out


func _categories(res: Resource) -> Array:
	var out: Array = []
	for p in _props_of(res):
		if not out.has(p.category):
			out.append(p.category)
	return out


## Редактируемые поля ресурса: bool, int, float, Color, сгруппированные по @export_category
func _props_of(res: Resource) -> Array:
	var out: Array = []
	var cat := ""
	for p in res.get_property_list():
		if p.usage & PROPERTY_USAGE_CATEGORY:
			cat = String(p.name)
			continue
		if not (p.usage & PROPERTY_USAGE_EDITOR) or not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_COLOR].has(p.type):
			continue
		out.append({"category": cat, "name": String(p.name), "type": p.type,
				"hint": p.hint, "hint_string": String(p.hint_string)})
	return out


func _snapshot(res: Resource) -> Dictionary:
	var d := {}
	for p in _props_of(res):
		d[p.name] = res.get(p.name)
	return d


func _build_groups(res: Resource, k: Dictionary) -> void:
	var folds := {}
	for p in _props_of(res):
		var gid: String = k.kind + ":" + p.category
		if not folds.has(gid):
			var fold := FoldableContainer.new()
			fold.title = "%s · %s" % [k.title, p.category]
			fold.folded = _closed.has(gid)
			fold.folding_changed.connect(_on_folded.bind(gid))
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override(&"h_separation", 6)
			fold.add_child(grid)
			_body.add_child(fold)
			folds[gid] = grid
		_add_row(folds[gid], res, p)


func _on_folded(is_folded: bool, gid: String) -> void:
	if is_folded and not _closed.has(gid):
		_closed.append(gid)
	elif not is_folded:
		_closed.erase(gid)
	Settings.set_value(SETTINGS_SECTION, CLOSED_KEY, _closed)


func _add_row(grid: GridContainer, res: Resource, p: Dictionary) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override(&"separation", -2)
	var label := Label.new()
	label.text = p.name.capitalize()
	cell.add_child(label)
	cell.add_child(make_var_label(p.name))
	grid.add_child(cell)

	var field: String = p.name
	var control: Control
	match p.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.size_flags_horizontal = Control.SIZE_SHRINK_END
			cb.toggled.connect(func(on: bool) -> void: _write(res, field, on))
			control = cb
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.edit_alpha = false
			cp.custom_minimum_size = Vector2(110.0, 28.0)
			cp.size_flags_horizontal = Control.SIZE_SHRINK_END
			cp.color_changed.connect(func(c: Color) -> void: _write(res, field, c))
			control = cp
		_:
			if p.type == TYPE_INT and p.hint == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				ob.size_flags_horizontal = Control.SIZE_SHRINK_END
				var idx := 0
				for part in String(p.hint_string).split(","):
					var kv := part.split(":")
					var val := int(kv[1]) if kv.size() > 1 else idx
					ob.add_item(kv[0], val)
					idx = val + 1
				ob.item_selected.connect(func(i: int) -> void: _write(res, field, ob.get_item_id(i)))
				control = ob
			else:
				var is_int: bool = p.type == TYPE_INT
				var lo := -100000.0
				var hi := 100000.0
				var step := 1.0 if is_int else _float_step(float(res.get(field)))
				if p.hint == PROPERTY_HINT_RANGE:
					var parts := String(p.hint_string).split(",")
					if parts.size() >= 2:
						lo = float(parts[0])
						hi = float(parts[1])
					if parts.size() >= 3 and parts[2].is_valid_float():
						step = float(parts[2])
				var spin := make_spin(lo, hi, step)
				spin.allow_lesser = true
				spin.value_changed.connect(func(v: float) -> void: _write(res, field, _as_number(v, is_int)))
				control = spin
	grid.add_child(control)

	var reset := Button.new()
	reset.text = "R"
	reset.flat = true
	reset.tooltip_text = "Вернуть значение на момент первого показа пресета"
	reset.pressed.connect(func() -> void: _reset_one(res, field))
	grid.add_child(reset)

	var r := {"res": res, "name": field, "type": p.type, "control": control}
	_rows.append(r)
	_read_row(r)


## Шаг поля по величине значения: мелкие значения правим сотыми, крупные целыми
static func _float_step(v: float) -> float:
	return 0.01 if absf(v) < 20.0 else 1.0


func _read_row(r: Dictionary) -> void:
	var v: Variant = (r.res as Resource).get(r.name)
	var c: Control = r.control
	if c is CheckBox:
		(c as CheckBox).set_pressed_no_signal(bool(v))
	elif c is ColorPickerButton:
		var cp := c as ColorPickerButton
		if cp.color != v:
			cp.color = v
	elif c is OptionButton:
		var ob := c as OptionButton
		var i := ob.get_item_index(int(v))
		if i >= 0:
			ob.select(i)
	elif c is SpinBox:
		set_spin(c as SpinBox, float(v))


## int или float по типу поля (тернарник int/float даёт предупреждение INCOMPATIBLE_TERNARY)
func _as_number(v: float, as_int: bool) -> Variant:
	if as_int:
		return int(v)
	return v


func _write(res: Resource, field: String, value: Variant) -> void:
	res.set(field, value)
	GFX.reapply(_meta[res].kind == "quality")


func _reset_one(res: Resource, field: String) -> void:
	if not _bases.has(res):
		return
	_write(res, field, _bases[res][field])
	refresh()


func _reset_all() -> void:
	for res in _bases:
		for field in _bases[res]:
			res.set(field, _bases[res][field])
	GFX.reapply(true)
	refresh()


# --- отличия и запись ---

## Отличия по всем пресетам, которые правились: Array[{res, field, old, value}]
func _diff() -> Array:
	var out: Array = []
	for res in _bases:
		for field in _bases[res]:
			var old: Variant = _bases[res][field]
			var cur: Variant = res.get(field)
			if not _same(old, cur):
				out.append({"res": res, "field": field, "old": old, "value": cur})
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return a == b


func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return String.num(v, 4)
	return var_to_str(v)


func _label_of(res: Resource) -> String:
	return "%s %s" % [_meta[res].title, res.get("id")]


func _update_buttons() -> void:
	var changed := not _diff().is_empty()
	_passport_btn.disabled = not changed
	_copy_btn.disabled = not changed


func _ask_save() -> void:
	var diff := _diff()
	if diff.is_empty():
		return
	var text := "Записать в пресеты (.tres в проекте)?\n\n"
	var seen := {}
	for d in diff:
		if not seen.has(d.res):
			seen[d.res] = true
			text += "%s -> %s\n" % [_label_of(d.res), _path_of(d.res)]
	text += "\n"
	for d in diff:
		text += "%s.%s: %s -> %s\n" % [d.res.get("id"), d.field, _fmt(d.old), _fmt(d.value)]
	text += "\nПресет пишется целиком. Файл лежит в проекте: его надо закоммитить."
	_confirm.dialog_text = text
	_confirm.popup_centered(Vector2i(520, 0))


func _path_of(res: Resource) -> String:
	if res.resource_path.begins_with("res://") and not res.resource_path.contains("::"):
		return res.resource_path
	return String(_meta[res].dir) + String(res.get("id")) + ".tres"


func _write_presets() -> void:
	var seen := {}
	var lines := PackedStringArray()
	var ok := true
	for d in _diff():
		seen[d.res] = true
	for res in seen:
		var path := _path_of(res)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := ResourceSaver.save(res, path)
		if err == OK:
			res.take_over_path(path)
			_bases[res] = _snapshot(res)   # «Вернуть все» теперь возвращает к записанному
			lines.append("Записан " + path)
		else:
			ok = false
			lines.append("Ошибка %d: %s" % [err, path])
	_status.text = "\n".join(lines)
	_status.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.5, 0.4))
	_status.show()
	_update_buttons()


func _copy_diff() -> void:
	var text := ""
	var cur: Resource = null
	for d in _diff():
		if d.res != cur:
			cur = d.res
			text += "[%s]\n" % _label_of(cur)
		text += "%s = %s\n" % [d.field, _fmt(d.value)]
	DisplayServer.clipboard_set(text)
	_status.text = "Отличия скопированы в буфер."
	_status.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.7))
	_status.show()
