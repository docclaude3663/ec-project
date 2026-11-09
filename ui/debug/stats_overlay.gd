class_name StatsOverlay extends CanvasLayer

###########################
## Оверлей статистики в углу экрана для прогонов (стенд, замеры)
###########################
## Только отладочная сборка: создаёт и держит GFX (GFX.stats). Включает клавиша F4, галочка в F3 → Toggles и комната со
## show_stats (стенд «bench»). Обновляется 4 раза в секунду, обход сущностей копеечный.
## Отрисовка и треугольники читаются из Performance-мониторов Godot: это ВСЕ проходы кадра (основной, тени, depth prepass),
## поэтому цифры выше, чем «видно на экране», но для сравнения прогонов между собой годятся.
## Угол экрана: CORNER. ModePanel занимает верхний правый, доки инструментов нижний левый.

const REFRESH := 0.25
const MARGIN := 8.0
const CORNER := Control.PRESET_TOP_LEFT   # или PRESET_BOTTOM_RIGHT

var _label: Label
var _acc := REFRESH


func _init() -> void:
	name = &"StatsOverlay"
	layer = 120
	visible = false
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override(&"panel", sb)
	# Угол: якорь в углу, панель растёт внутрь экрана
	panel.set_anchors_preset(CORNER)
	var right := CORNER == Control.PRESET_TOP_RIGHT or CORNER == Control.PRESET_BOTTOM_RIGHT
	var bottom := CORNER == Control.PRESET_BOTTOM_LEFT or CORNER == Control.PRESET_BOTTOM_RIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	var ox := -MARGIN if right else MARGIN
	var oy := -MARGIN if bottom else MARGIN
	panel.offset_left = ox
	panel.offset_right = ox
	panel.offset_top = oy
	panel.offset_bottom = oy
	add_child(panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 13)
	panel.add_child(_label)


func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	if _acc >= REFRESH:
		_acc = 0.0
		_label.text = _text()


func set_shown(on: bool) -> void:
	visible = on
	_acc = REFRESH   # обновить сразу


func _text() -> String:
	var fps := Engine.get_frames_per_second()
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var c := _count_entities()
	var lines: Array[String] = []
	lines.append("FPS %d   кадр %.1f мс   физика %.1f мс" % [fps, frame_ms, phys_ms])
	lines.append("Draw calls %d   Треугольники %s   Объектов %d" % [draws, _short(tris), objs])
	lines.append("Траки %d (flex %d, стрелок %d)   Вагоны %d   Всего сущностей %d" % [c.tracks, c.flex, c.switches, c.wagons, c.total])
	lines.append("Тел физики %d   Узлов %d   VRAM %.0f МБ" % [
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), vram])
	lines.append(_run_line())
	return "\n".join(lines)


## Условия прогона: комната, пресеты, экран, физика
func _run_line() -> String:
	var st: Dictionary = GFX.get_state()
	var vsync := "V-Sync вкл" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "V-Sync выкл"
	var win := get_window().size
	var s := "Комната %s   %s   %s/%s   %s   %dx%d" % [_room_id(), st.get("quality", "?"), st.get("look", "?"), st.get("time", "?"),
			vsync, win.x, win.y]
	var scale3d := get_viewport().scaling_3d_scale
	if not is_equal_approx(scale3d, 1.0):
		s += "   3D x%.2f" % scale3d
	s += "   физика %d Гц" % Engine.physics_ticks_per_second
	if not is_equal_approx(Engine.time_scale, 1.0):
		s += "   время x%.2f" % Engine.time_scale
	return s


func _room_id() -> String:
	var rb := get_tree().get_first_node_in_group(&"room_root")
	if rb == null:
		return "?"
	var cfg := rb.get("config") as RoomConfig
	return String(cfg.id) if cfg else "?"


## Траки (C_Path или стрелка), из них flex (C_FlexShape) и стрелки (C_Switch); вагоны (C_Bogie: вагоны и локомотивы). Призраки не считаются.
## flex и стрелки показаны в скобках как справка, поэтому в «траках» они уже учтены, если у них есть C_Path
func _count_entities() -> Dictionary:
	var out := {"tracks": 0, "flex": 0, "wagons": 0, "switches": 0, "total": 0}
	var root := get_node_or_null("/root/GameRoot/EntitiesRoot")
	if root == null:
		return out
	for n in root.get_children():
		var e := n as Entity
		if e == null or e.has_comp(C_Ghost):
			continue
		out["total"] += 1
		var is_switch := e.has_comp(C_Switch)
		if e.has_comp(C_Path) or is_switch:
			out["tracks"] += 1
		if e.has_comp(C_FlexShape):
			out["flex"] += 1
		if is_switch:
			out["switches"] += 1
		if e.has_comp(C_Bogie):
			out["wagons"] += 1
	return out


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
