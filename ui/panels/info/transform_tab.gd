class_name InfoTransformTab extends InfoTab

###########################
## Вкладка «Положение»: координаты, поворот, «на траке»
###########################
## Узлы в info_panel.tscn (TransformTab). Тюнинг физики вагона и скорость переехали в DebugPanel (U14),
## спидометр и его галочка убраны до U23 (ATTN_17 §17.x «Инструменты-сущности»).

const ON_TRACK_COLOR := Color(0.4, 1.0, 0.5)

var _chassis: C_Chassis
var _coupler: C_Coupler
## Строки «Сцепка» создаются кодом в сетке рядом с «На траке»: [передняя, задняя] пары (подпись, значение)
var _coupler_rows: Array = []
## Кнопка «Записать состав» и строка результата под ней (создаются кодом)
var _record_button: Button
var _record_label: Label


func _on_bind() -> void:
	_build_coupler_rows()
	components_changed()
	refresh()


func _on_unbind() -> void:
	_chassis = null
	_coupler = null
	if _record_label:
		_record_label.text = ""


func components_changed() -> void:
	if target == null:
		return
	_chassis = target.get_comp(C_Chassis) as C_Chassis
	_coupler = target.get_comp(C_Coupler) as C_Coupler


func refresh() -> void:
	if target == null:
		return
	var pos := target.global_position
	var rot := target.rotation_degrees
	_n("PosLabel").text = "(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
	_n("RotLabel").text = "(%.2f, %.2f, %.2f)" % [rot.x, rot.y, rot.z]
	_set_on_track()
	_set_couplers()


## «На траке»: да (зеленым) или нет (цвет по умолчанию). У объектов без шасси прочерк
func _set_on_track() -> void:
	var label := _n("OnTrackLabel") as Label
	if _chassis == null:
		label.text = "-"
		label.remove_theme_color_override(&"font_color")
	elif _chassis.is_on_rails:
		label.text = "Да"
		label.add_theme_color_override(&"font_color", ON_TRACK_COLOR)
	else:
		label.text = "Нет"
		label.remove_theme_color_override(&"font_color")


## Один раз добавляет в сетку «На траке» две строки: сцепка спереди и сзади
func _build_coupler_rows() -> void:
	if not _coupler_rows.is_empty():
		return
	var grid := (_n("OnTrackLabel") as Label).get_parent()
	for title in ["Сцепка спереди:", "Сцепка сзади:"]:
		var caption := Label.new()
		caption.text = title
		var value := Label.new()
		grid.add_child(caption)
		grid.add_child(value)
		_coupler_rows.append([caption, value])
	# Кнопка записи состава: в вертикальном контейнере вкладки, под сеткой
	var box := grid.get_parent().get_parent()
	_record_button = Button.new()
	_record_button.text = "Записать состав"
	_record_button.tooltip_text = "Сохранить все сцепленные вагоны как кнопку «Составы» в каталоге"
	_record_button.pressed.connect(_on_record_pressed)
	box.add_child(_record_button)
	_record_label = Label.new()
	_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_record_label)


## Статус сцепки: у объектов без C_Coupler строки скрыты, вечная сцепка выделена цветом
func _set_couplers() -> void:
	if _record_button:
		var chain_len := _coupler.get_consist().size() if _coupler else 0
		_record_button.visible = chain_len >= 2
		_record_label.visible = _coupler != null
	for end in _coupler_rows.size():
		var caption := _coupler_rows[end][0] as Label
		var value := _coupler_rows[end][1] as Label
		caption.visible = _coupler != null
		value.visible = _coupler != null
		if _coupler == null:
			continue
		value.text = _coupler.end_status(end)
		if _coupler.is_permanent(end):
			value.add_theme_color_override(&"font_color", ON_TRACK_COLOR)
		else:
			value.remove_theme_color_override(&"font_color")


func _on_record_pressed() -> void:
	if target == null:
		return
	var res := ConsistStore.record(target)
	_record_label.text = ("Записано: %s" % res["name"]) if res["ok"] else ("Не записано: %s" % res["error"])
