class_name DebugTuningTab extends DebugTab

###########################
## Вкладки «Tuning» и «Suspension»: настройка выбранного вагона (U14)
###########################
## Один класс на три вкладки: tab_id выбирает группы из WagonTuning.GROUPS (Tuning: физика, мотор, сцепка, тело;
## Suspension: включатели и SuspensionConfig; Layout: высота меша и тележки, с линиями уровней в 3D). Группы сворачиваются, как категории в инспекторе паспорта, состояние
## хранится в Settings [debug] closed_<вкладка>. Строки строятся один раз по WagonTuning.params(); при выборе
## показываются только те, что есть у цели, а группы без компонента перечислены строкой «Нет у этого объекта».
## Кнопка «R» у строки и «Вернуть все» возвращают значения на момент выбора вагона.
## Значения живут в компонентах вагона и не сохраняются в макет. Чтобы оставить подобранное, «В паспорт»
## записывает отличия в паспорт типа вагона (.tres): новые вагоны этого типа возьмут значения оттуда.

const SETTINGS_SECTION := "debug"

var tab_id: String

## Строки: key -> {control, kind, nodes: Array[Control], group}
var _rows: Dictionary = {}
## Группы: id -> FoldableContainer
var _folds: Dictionary = {}
## Значения на момент выбора вагона
var _baseline: Dictionary = {}
## id свернутых групп
var _closed: Array = []

var _title: Label
var _hint: Label
var _body: VBoxContainer
var _absent: Label
var _passport_btn: Button
var _copy_btn: Button
var _status: Label
var _confirm: ConfirmationDialog
var _levels_check: CheckBox
var _flange_spin: SpinBox
var _overlay: DebugLayoutOverlay


func _init(p_tab_id: String = WagonTuning.TAB_TUNING) -> void:
	tab_id = p_tab_id
	match tab_id:
		WagonTuning.TAB_SUSPENSION: name = &"Suspension"
		WagonTuning.TAB_LAYOUT: name = &"Layout"
		_: name = &"Tuning"
	_closed = _load_closed()

	_title = Label.new()
	_title.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5))
	add_child(_title)
	_hint = make_note("Выберите вагон в режиме Select.")
	add_child(_hint)

	_body = VBoxContainer.new()
	add_child(_body)

	if tab_id == WagonTuning.TAB_LAYOUT:
		_levels_check = CheckBox.new()
		_levels_check.text = "Показать уровни (рельс, колеса, меш)"
		_levels_check.tooltip_text = "Линии и числа в 3D: колесо должно стоять на рельсе (разница 0)"
		_levels_check.toggled.connect(func(_on: bool) -> void: _update_overlay())
		_body.add_child(_levels_check)
		var flange_row := HBoxContainer.new()
		_body.add_child(flange_row)
		var flange_label := Label.new()
		flange_label.text = "Высота реборды, м"
		flange_label.tooltip_text = "Из меша колеса высота реборды неизвестна: задайте ее сами. Низ колеса без реборды считается от нее"
		flange_label.mouse_filter = Control.MOUSE_FILTER_PASS
		flange_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flange_row.add_child(flange_label)
		_flange_spin = make_spin(0.0, 1.0, 0.005)
		_flange_spin.set_value_no_signal(float(Settings.get_value(SETTINGS_SECTION, "flange_height", 0.13)))
		_flange_spin.value_changed.connect(_on_flange_changed)
		flange_row.add_child(_flange_spin)
		_body.add_child(make_note("Желтая линия: поверхность катания (головка рельса). Синяя: низ колеса без реборды. Голубая: верх колеса с ребордой. Фиолетовая: плоскость меша. «Колесо-рельс» = синяя минус желтая: 0 колесо стоит на рельсе, плюс в воздухе, минус утоплено. Крутите высоту тележки, пока не будет 0, затем высоту меша. Паспорт не меняется, пока не нажмете «В паспорт»."))

	var reset_all := Button.new()
	reset_all.text = "Вернуть все (как при выборе)"
	reset_all.pressed.connect(_reset_all)
	_body.add_child(reset_all)

	var passport_row := HBoxContainer.new()
	_body.add_child(passport_row)
	_passport_btn = Button.new()
	_passport_btn.text = "В паспорт..."
	_passport_btn.pressed.connect(_ask_passport)
	passport_row.add_child(_passport_btn)
	_copy_btn = Button.new()
	_copy_btn.text = "Копировать"
	_copy_btn.tooltip_text = "Скопировать отличия от паспорта текстом «поле = значение»"
	_copy_btn.pressed.connect(_copy_diff)
	passport_row.add_child(_copy_btn)
	_status = make_note("")
	_status.hide()
	_body.add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "В паспорт"
	_confirm.ok_button_text = "Записать"
	_confirm.dialog_autowrap = true
	_confirm.confirmed.connect(_write_passport)
	add_child(_confirm)

	for g in WagonTuning.GROUPS:
		if g.tab != tab_id:
			continue
		var fold := FoldableContainer.new()
		fold.title = g.title
		fold.folded = _closed.has(g.id)
		fold.folding_changed.connect(_on_folded.bind(g.id))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", 6)
		fold.add_child(grid)
		_body.add_child(fold)
		_folds[g.id] = fold

	for p in WagonTuning.params():
		if p.tab == tab_id:
			_add_row(p)

	_absent = make_note("")
	_body.add_child(_absent)
	_body.hide()


## Свернутые группы: из настроек, а если там пусто (первый запуск), свернуты все кроме первой группы вкладки
func _load_closed() -> Array:
	var saved: Variant = Settings.get_value(SETTINGS_SECTION, "closed_" + tab_id, null)
	if saved is Array:
		return saved
	var result: Array = []
	var first := true
	for g in WagonTuning.GROUPS:
		if g.tab != tab_id:
			continue
		if not first:
			result.append(g.id)
		first = false
	return result


func _on_folded(is_folded: bool, group_id: String) -> void:
	if is_folded and not _closed.has(group_id):
		_closed.append(group_id)
	elif not is_folded:
		_closed.erase(group_id)
	Settings.set_value(SETTINGS_SECTION, "closed_" + tab_id, _closed)


func _add_row(p: Dictionary) -> void:
	var grid := (_folds[p.group] as FoldableContainer).get_child(0) as GridContainer
	# Ячейка подписи: название и, мелко, имя переменной (показывается кнопкой в заголовке панели)
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_PASS   # без этого тултип на подписи не покажется
	cell.add_theme_constant_override(&"separation", -2)
	if p.tip != "":
		cell.tooltip_text = p.tip
	var label := Label.new()
	label.text = p.label
	cell.add_child(label)
	cell.add_child(make_var_label(WagonTuning.var_name(p.key)))
	grid.add_child(cell)

	var key: String = p.key
	var control: Control
	if p.kind == WagonTuning.Kind.TOGGLE:
		var cb := CheckBox.new()
		cb.size_flags_horizontal = Control.SIZE_SHRINK_END
		cb.toggled.connect(func(on: bool) -> void: WagonTuning.write(target, key, on))
		control = cb
	else:
		var spin := make_spin(p.min, p.max, p.step)
		spin.value_changed.connect(func(v: float) -> void: WagonTuning.write(target, key, v))
		control = spin
	grid.add_child(control)

	var reset := Button.new()
	reset.text = "R"
	reset.flat = true
	reset.tooltip_text = "Вернуть значение, которое было при выборе вагона"
	reset.pressed.connect(func() -> void: _reset_one(key))
	grid.add_child(reset)

	_rows[key] = {"control": control, "kind": p.kind, "nodes": [cell, control, reset], "group": p.group}


func _on_bind() -> void:
	_baseline.clear()
	_status.hide()
	_free_overlay()
	var wagon := WagonTuning.is_wagon(target)
	_body.visible = wagon
	_hint.visible = not wagon
	if not wagon:
		_title.text = "Нет вагона" if target == null else "%s: не вагон" % target.name
		return
	_title.text = str(target.name)
	_baseline = WagonTuning.snapshot(target)
	# Показываем только ручки, которые есть у цели
	var shown := {}
	for key in _rows:
		var row: Dictionary = _rows[key]
		var has_it := _baseline.has(key)
		for n: Control in row.nodes:
			n.visible = has_it
		if has_it:
			shown[row.group] = true
	var absent: PackedStringArray = []
	for gid in _folds:
		(_folds[gid] as FoldableContainer).visible = shown.has(gid)
		if not shown.has(gid):
			absent.append("%s: %s" % [_group_title(gid), WagonTuning.missing_reason(gid)])
	_absent.visible = not absent.is_empty()
	_absent.text = "Нет у этого объекта:\n" + "\n".join(absent)
	_fill_controls(true)
	_update_overlay()


func closed() -> void:
	_free_overlay()


## Линии уровней показываются у выбранного вагона, пока включена галочка и открыта панель
func _update_overlay() -> void:
	_free_overlay()
	if _levels_check == null or not _levels_check.button_pressed or not WagonTuning.is_wagon(target):
		return
	_overlay = DebugLayoutOverlay.new()
	_overlay.flange_height = _flange_spin.value
	target.get_tree().current_scene.add_child(_overlay)
	_overlay.setup(target)


func _on_flange_changed(value: float) -> void:
	Settings.set_value(SETTINGS_SECTION, "flange_height", value)
	if is_instance_valid(_overlay):
		_overlay.flange_height = value


func _free_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _group_title(group_id: String) -> String:
	for g in WagonTuning.GROUPS:
		if g.id == group_id:
			return g.title
	return group_id


func refresh() -> void:
	if not WagonTuning.is_wagon(target):
		# Вагон удалили, пока он был выбран
		if _body.visible:
			_on_bind()
		return
	_fill_controls(false)


## Читает значения из вагона в контролы (без сигналов; поле в фокусе не трогаем)
func _fill_controls(force: bool) -> void:
	for key in _rows:
		var row: Dictionary = _rows[key]
		if not _baseline.has(key):
			continue
		var v: Variant = WagonTuning.read(target, key)
		if v == null:
			continue
		if row.kind == WagonTuning.Kind.TOGGLE:
			(row.control as CheckBox).set_pressed_no_signal(bool(v))
		elif force:
			(row.control as SpinBox).set_value_no_signal(float(v))
		else:
			set_spin(row.control as SpinBox, float(v))
	_update_passport_buttons()


## Кнопки паспорта доступны, когда вагон чем-то отличается от паспорта и паспорт есть куда записать
func _update_passport_buttons() -> void:
	var changed := not WagonTuning.passport_diff(target, tab_id).is_empty()
	var can_write := WagonTuning.passport_path(target) != ""
	_passport_btn.disabled = not (changed and can_write)
	_passport_btn.tooltip_text = "Записать отличия в паспорт типа вагона (.tres)" if can_write \
			else "Паспорт не лежит в отдельном .tres, записывать некуда"
	_copy_btn.disabled = not changed


func _ask_passport() -> void:
	var diff := WagonTuning.passport_diff(target, tab_id)
	if diff.is_empty():
		return
	var text := "Записать в паспорт типа вагона?\n%s\n\n" % WagonTuning.passport_path(target)
	for d in diff:
		text += "%s: %s -> %s\n" % [d.field, String.num(d.old, 4), String.num(d.value, 4)]
	text += "\nПаспорт общий для всех вагонов этого типа. Уже стоящие вагоны не изменятся, новые будут с этими значениями."
	if tab_id == WagonTuning.TAB_SUSPENSION:
		text += " У стоящих вагонов с тем же паспортом подвеска может частично подхватить значения сразу (стыки, рыскание), остальное после пересоздания."
	text += " Параметры без пометки паспорта (включатели, тело, ощущение сцепки) не записываются."
	_confirm.dialog_text = text
	_confirm.popup_centered(Vector2i(480, 0))


func _write_passport() -> void:
	var result := WagonTuning.save_to_passport(target, tab_id)
	_status.text = result.message
	_status.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5) if result.ok else Color(1.0, 0.5, 0.4))
	_status.show()
	if result.ok:
		# «Вернуть все» теперь возвращает к записанному, а не к значениям до записи
		_baseline = WagonTuning.snapshot(target)
	_update_passport_buttons()


func _copy_diff() -> void:
	DisplayServer.clipboard_set(WagonTuning.passport_diff_text(target, tab_id))
	_status.text = "Отличия от паспорта скопированы в буфер."
	_status.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.7))
	_status.show()


func _reset_one(key: String) -> void:
	if not _baseline.has(key) or not WagonTuning.is_wagon(target):
		return
	WagonTuning.write(target, key, _baseline[key])
	_fill_controls(true)


func _reset_all() -> void:
	if not WagonTuning.is_wagon(target):
		return
	WagonTuning.restore(target, _baseline)
	_fill_controls(true)
