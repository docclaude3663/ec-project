extends "res://core/library/workspace/workspace.gd"

# XX claude-library (новый файл)
########################
## Покраска: грунт по зонам, исполнения модели (ATTN_22 §22.7.2.1, шаг L3)
########################
## Правит screen.variant (буфер исполнения текущей модели) и сразу применяет его к мешам кузова
## (screen.apply_variant). Зоны: «Весь корпус» и каждая поверхность каждого меша (PaintZones).
## Уровни paint.level: 0 покраска выключена; 1 только цвет зоны; 2 плюс отделка и кроющая/лессировка.
## Исполнения хранятся JSON в user://library/variants/ (VariantIO); «Сохранить» обновляет открытое исполнение,
## «Как новое» создаёт копию. Несохранённые правки теряются при выборе другой модели.

const PALETTE := [
	["Белый", "#f2f2f0"], ["Чёрный", "#1b1b1d"], ["Серый", "#7d7f82"], ["Красный", "#c0392b"],
	["Тёмно-красный", "#7a1f1f"], ["Оранжевый", "#e67e22"], ["Жёлтый", "#f1c40f"], ["Зелёный", "#2e9e5b"],
	["Тёмно-зелёный", "#1f5a3a"], ["Голубой", "#3b9ae1"], ["Синий", "#1f4e9c"], ["Коричневый", "#6b4226"],
]

var _note: Label
var _controls: VBoxContainer
var _zone_opt: OptionButton
var _color_btn: ColorPickerButton
var _finish_row: HBoxContainer
var _finish_opt: OptionButton
var _cover_check: CheckBox
var _name_edit: LineEdit
var _saved_list: ItemList
var _status: Label
var _zones: Array[Dictionary] = []
var _saved: Array[ModelVariant] = []
var _silent := false   # идёт программное заполнение элементов, их обработчики молчат


func _init() -> void:
	id = &"paint"
	title = "Покраска"


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)
	scroll.add_child(card)

	var head := Label.new()
	head.text = "Покраска"
	head.add_theme_font_size_override("font_size", 18)
	card.add_child(head)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_note)

	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 6)
	card.add_child(_controls)

	_controls.add_child(_caption("Зона"))
	_zone_opt = OptionButton.new()
	_zone_opt.item_selected.connect(func(_i: int) -> void: _sync_controls())
	_controls.add_child(_zone_opt)

	_controls.add_child(_caption("Цвет"))
	_color_btn = ColorPickerButton.new()
	_color_btn.edit_alpha = false
	_color_btn.custom_minimum_size = Vector2(0, 28)
	_color_btn.color = Color.from_string(PALETTE[3][1], Color.RED)
	_color_btn.color_changed.connect(func(_c: Color) -> void: _apply_zone())
	_controls.add_child(_color_btn)
	var grid := GridContainer.new()
	grid.columns = 6
	for p in PALETTE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(32, 28)
		b.tooltip_text = p[0]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.from_string(p[1], Color.WHITE)
		sb.set_corner_radius_all(3)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_pick_palette.bind(p[1]))
		grid.add_child(b)
	_controls.add_child(grid)

	_finish_row = HBoxContainer.new()
	_controls.add_child(_finish_row)
	_finish_opt = OptionButton.new()
	_finish_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in PaintData.FINISH_ORDER:
		_finish_opt.add_item(str(PaintData.FINISHES[key]["name"]))
		_finish_opt.set_item_metadata(_finish_opt.item_count - 1, key)
	_finish_opt.item_selected.connect(func(_i: int) -> void: _apply_zone(false))
	_finish_row.add_child(_finish_opt)
	_cover_check = CheckBox.new()
	_cover_check.text = "Кроющая"
	_cover_check.button_pressed = true
	_cover_check.tooltip_text = "Кроющая краска закрывает рисунок модели. Без галочки цвет накладывается на рисунок (лессировка)."
	_cover_check.toggled.connect(func(_on: bool) -> void: _apply_zone(false))
	_finish_row.add_child(_cover_check)

	var row := HBoxContainer.new()
	_controls.add_child(row)
	var reset_zone := Button.new()
	reset_zone.text = "Сбросить зону"
	reset_zone.pressed.connect(_on_reset_zone)
	row.add_child(reset_zone)
	var reset_all := Button.new()
	reset_all.text = "Сбросить всё"
	reset_all.pressed.connect(_on_reset_all)
	row.add_child(reset_all)

	_controls.add_child(HSeparator.new())
	_controls.add_child(_caption("Исполнения"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Название исполнения"
	_controls.add_child(_name_edit)
	var row2 := HBoxContainer.new()
	_controls.add_child(row2)
	var save := Button.new()
	save.text = "Сохранить"
	save.pressed.connect(_on_save.bind(false))
	row2.add_child(save)
	var save_new := Button.new()
	save_new.text = "Как новое"
	save_new.pressed.connect(_on_save.bind(true))
	row2.add_child(save_new)
	_saved_list = ItemList.new()
	_saved_list.custom_minimum_size = Vector2(0, 110)
	_saved_list.item_activated.connect(func(_i: int) -> void: _on_load())
	_controls.add_child(_saved_list)
	var row3 := HBoxContainer.new()
	_controls.add_child(row3)
	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.pressed.connect(_on_load)
	row3.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "Удалить"
	del_btn.pressed.connect(_on_delete)
	row3.add_child(del_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.6)
	add_child(_status)


func enter() -> void:
	_refresh()


func on_loading(_setting: EntitySetting) -> void:
	_status.text = ""


func on_subject(_setting: EntitySetting, _info: Dictionary, _ms: int) -> void:
	_refresh()


# ==========================================
# СОСТОЯНИЕ
# ==========================================

func _paint_level() -> int:
	return screen.rules.level(LibraryRules.K_PAINT)


func _refresh() -> void:
	var meshes: Array = screen.body_meshes()
	var level := _paint_level()
	var locked: bool = screen.is_current_locked()
	var usable := level > 0 and not locked and not meshes.is_empty()
	_controls.visible = usable
	if level == 0:
		_note.text = "Покраска отключена правилами (%s)." % screen.rules.label()
	elif locked:
		_note.text = "Модель закрыта: красить можно только открытые модели."
	elif meshes.is_empty():
		_note.text = "У модели нет мешей для покраски."
	else:
		_note.text = "Выберите зону и цвет: покраска применяется сразу. Несохранённые правки пропадут при выборе другой модели."
	if not usable:
		return
	_finish_row.visible = level >= 2
	_build_zone_list()
	_sync_controls()
	_refresh_saved()


func _build_zone_list() -> void:
	var keep := _selected_zone_id()
	var key: StringName = screen.current_setting.get_key() if screen.current_setting != null else &""
	_zones = PaintZones.list(screen.body_meshes(), ModelInfo.find(key))
	_silent = true
	_zone_opt.clear()
	var painted := PaintData.zones(screen.variant.paint)
	var select := 0
	for i in _zones.size():
		var z := _zones[i]
		var mark := "  ●" if painted.has(z["id"]) else ""
		_zone_opt.add_item(str(z["title"]) + mark)
		if z["id"] == keep:
			select = i
	_zone_opt.select(select)
	_silent = false


func _selected_zone_id() -> String:
	var i := _zone_opt.selected if _zone_opt != null else -1
	if i < 0 or i >= _zones.size():
		return PaintData.ALL
	return str(_zones[i]["id"])


## Элементы показывают состояние выбранной зоны из исполнения
func _sync_controls() -> void:
	if _silent:
		return
	_silent = true
	var spec := PaintData.zone_spec(screen.variant.paint, _selected_zone_id())
	if not spec.is_empty():
		_color_btn.color = Color.from_string(str(spec["color"]), _color_btn.color)
		_cover_check.button_pressed = bool(spec["cover"])
		var idx := PaintData.FINISH_ORDER.find(str(spec["finish"]))
		_finish_opt.select(maxi(idx, 0))
	_silent = false


## Записать в зону то, что выбрано в элементах, и применить. color_changed: создаёт зону.
## Отделка и «кроющая» меняют только уже окрашенную зону (чтобы не красить зону случайно)
func _apply_zone(create := true) -> void:
	if _silent:
		return
	var zone := _selected_zone_id()
	if not create and PaintData.zone_spec(screen.variant.paint, zone).is_empty():
		return
	var finish := str(_finish_opt.get_item_metadata(_finish_opt.selected))
	if _paint_level() < 2:
		finish = "keep"
	var cover := _cover_check.button_pressed if _paint_level() >= 2 else true
	PaintData.set_zone(screen.variant.paint, zone, _color_btn.color, finish, cover)
	screen.apply_variant()
	_mark_painted()


func _pick_palette(hex: String) -> void:
	_color_btn.color = Color.from_string(hex, _color_btn.color)
	_apply_zone()


func _mark_painted() -> void:
	var painted := PaintData.zones(screen.variant.paint)
	for i in _zones.size():
		var z := _zones[i]
		_zone_opt.set_item_text(i, str(z["title"]) + ("  ●" if painted.has(z["id"]) else ""))


func _on_reset_zone() -> void:
	PaintData.clear_zone(screen.variant.paint, _selected_zone_id())
	screen.apply_variant()
	_mark_painted()


func _on_reset_all() -> void:
	PaintData.clear_all(screen.variant.paint)
	screen.apply_variant()
	_mark_painted()


# ==========================================
# ИСПОЛНЕНИЯ
# ==========================================

func _refresh_saved() -> void:
	_saved_list.clear()
	if screen.current_setting == null:
		return
	_saved = VariantIO.list_variants(VariantIO.DEFAULT_DIR, String(screen.current_setting.get_key()))
	for v in _saved:
		_saved_list.add_item(v.name if v.name != "" else v.id)


func _on_save(as_new: bool) -> void:
	var v: ModelVariant = screen.variant
	if as_new or not ModelVariant.is_valid_id(v.id):
		v.id = ModelVariant.make_id()
	var typed := _name_edit.text.strip_edges()
	if typed != "":
		v.name = typed
	elif v.name == "":
		v.name = "Исполнение %d" % (_saved.size() + 1)
	_name_edit.text = v.name
	var err := VariantIO.save_variant(v)
	if err != OK:
		_status.text = "Не удалось сохранить исполнение (код %d)." % err
		return
	if not screen.profile.variants.has(v.id):
		screen.profile.variants.append(v.id)
		VariantIO.save_profile(screen.profile)
	_status.text = "Сохранено: %s." % v.name
	_refresh_saved()


func _on_load() -> void:
	var sel := _saved_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _saved.size():
		return
	var loaded := _saved[sel[0]].duplicate_variant()
	loaded.base = String(screen.current_setting.get_key())
	screen.variant = loaded
	_name_edit.text = loaded.name
	screen.apply_variant()
	_build_zone_list()
	_sync_controls()
	_status.text = "Загружено: %s." % loaded.name


func _on_delete() -> void:
	var sel := _saved_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _saved.size():
		return
	var v := _saved[sel[0]]
	VariantIO.delete_variant(v.id)
	screen.profile.variants.erase(v.id)
	VariantIO.save_profile(screen.profile)
	_status.text = "Удалено: %s." % (v.name if v.name != "" else v.id)
	_refresh_saved()


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l
