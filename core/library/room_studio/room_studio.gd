extends Control

# XX claude-library (новый файл)
########################
## Room Studio. Просмотрщик комнат (ATTN_22 §22.5.5, шаг L1c)
########################
## Инструмент автора в дочернем окне Library. Слева список комнат из RoomCatalog: у комнат со сценой (RoomConfig.scene)
## выбор доступен, процедурные (сцены нет) серые. Центр: отдельный World3D с нейтральным светом и свободной камерой, в нём
## экземпляр сцены комнаты как есть (RoomBuilder и GFX игры не используются, слои RoomRoot.setup не применяются).
## Справа паспорт только для чтения. Свет и небо игры здесь не показываются: их проверяют в Observe.
## Правки паспорта и комнаты в игре нет: это просмотр.

const StudioSettings := preload("res://core/library/icon_studio/studio_settings.gd")

const SETTINGS_PATH := "user://room_studio.cfg"
const HINT_TEXT := "ЛКМ: вращать   ·   Shift+ЛКМ, СКМ, ПКМ: сдвиг   ·   колесо: зум   ·   F: вписать"
const FOV := 40.0
const ORBIT_SPEED := 0.4
const PITCH_LIMIT := 89.0
const ZOOM_STEP := 1.12
const DIST_MIN := 20.0
const DIST_MAX := 4000.0
## Размеры мира в см (ATTN_14): комната около 5 м, поэтому дальняя плоскость далеко
const CAM_NEAR := 1.0
const CAM_FAR := 6000.0
const BG_COLOR := Color(0.16, 0.17, 0.19)

var settings: StudioSettings

var _entries: Array[Dictionary] = []    # {id, title, tip, cfg: RoomConfig, has_scene: bool}
var _list: ItemList
var _info: Label
var _ceiling_check: CheckButton
var _table_check: CheckButton
var _view_area: PanelContainer
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D            # корень мира: комната и стол-ориентир
var _room: Node3D
var _table: MeshInstance3D
var _current_id: StringName = &""
var _yaw := 35.0
var _pitch := 25.0
var _dist := 700.0
var _pivot := Vector3.ZERO
var _drag_button := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	settings = StudioSettings.new()
	settings.name = "StudioSettings"
	settings.path = SETTINGS_PATH
	add_child(settings)

	_load_entries()
	_build_ui()
	_build_world()
	_fill_list()

	# Размеры контейнеров известны только после первого кадра раскладки
	await get_tree().process_frame
	_select_initial()


func _exit_tree() -> void:
	if settings:
		settings.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and settings:
		settings.flush()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F and not k.ctrl_pressed:
		_fit()
		get_viewport().set_input_as_handled()


# ==========================================
# ДАННЫЕ
# ==========================================

## Все комнаты каталога; сцена есть у тех, чей паспорт из data/rooms ссылается на PackedScene
func _load_entries() -> void:
	_entries.clear()
	for e in RoomCatalog.entries():
		var cfg := RoomCatalog.make(e["id"])
		_entries.append({
			"id": e["id"],
			"title": e["title"],
			"tip": e["tip"],
			"cfg": cfg,
			"has_scene": cfg != null and cfg.scene != null,
		})


# ==========================================
# ИНТЕРФЕЙС
# ==========================================

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	# set_anchors_preset без offsets оставляет прежний (нулевой) размер, поэтому именно _and_offsets_
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)


func _build_left() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(280, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var title := Label.new()
	title.text = "Комнаты"
	v.add_child(title)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	v.add_child(_list)
	return p


func _build_center() -> Control:
	_view_area = PanelContainer.new()
	_view_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_area.custom_minimum_size = Vector2(320, 240)
	_view_area.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.11)
	_view_area.add_theme_stylebox_override("panel", bg)
	_view_area.gui_input.connect(_on_view_input)
	return _view_area


func _build_right() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(320, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var title := Label.new()
	title.text = "Паспорт"
	v.add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_info)
	v.add_child(HSeparator.new())
	_ceiling_check = CheckButton.new()
	_ceiling_check.text = "Потолок"
	_ceiling_check.tooltip_text = "Потолок скрыт по умолчанию: иначе внутрь комнаты не заглянуть"
	_ceiling_check.toggled.connect(func(_on: bool): _apply_toggles())
	v.add_child(_ceiling_check)
	_table_check = CheckButton.new()
	_table_check.text = "Стол-ориентир"
	_table_check.button_pressed = true
	_table_check.tooltip_text = "Столешница подмакетника по паспорту (table_top) на y = 0, только для масштаба: это не часть сцены комнаты"
	_table_check.toggled.connect(func(_on: bool): _apply_toggles())
	v.add_child(_table_check)
	return p


func _fill_list() -> void:
	_list.clear()
	for e in _entries:
		var i := _list.add_item(String(e["title"]))
		if e["has_scene"]:
			_list.set_item_tooltip(i, String(e["tip"]))
		else:
			_list.set_item_text(i, "%s (процедурная)" % e["title"])
			_list.set_item_disabled(i, true)
			_list.set_item_tooltip(i, "Процедурная комната: сцены нет, просмотр недоступен (ATTN_22 §22.5.5)")


## Последняя показанная комната или первая со сценой
func _select_initial() -> void:
	var last := StringName(str(settings.get_value("state", "last_id", "")))
	var pick := -1
	for i in _entries.size():
		if not _entries[i]["has_scene"]:
			continue
		if pick < 0:
			pick = i
		if _entries[i]["id"] == last:
			pick = i
			break
	if pick < 0:
		_info.text = "Нет комнат со сценой (data/rooms/<id>/<id>.tres)."
		return
	_list.select(pick)
	_show_room(pick)


func _on_selected(i: int) -> void:
	_show_room(i)


# ==========================================
# 3D-МИР
# ==========================================

func _build_world() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_area.add_child(svc)

	# Отдельный World3D: комната просмотра не видна игре и не видит её
	_vp = SubViewport.new()
	_vp.world_3d = World3D.new()
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	svc.add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	# Нейтральный свет без теней: комнату надо видеть, а не оценивать
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 0.6
	_vp.add_child(sun)

	_stage = Node3D.new()
	_stage.name = "Stage"
	_vp.add_child(_stage)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = CAM_NEAR
	_cam.far = CAM_FAR
	_vp.add_child(_cam)
	_cam.current = true
	_update_camera()


## Показать комнату i (только со сценой): прежняя комната освобождается
func _show_room(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var e: Dictionary = _entries[i]
	if not e["has_scene"]:
		return
	var cfg: RoomConfig = e["cfg"]
	_clear_room()
	_current_id = e["id"]
	settings.set_value("state", "last_id", String(_current_id))

	_room = cfg.scene.instantiate() as Node3D
	if _room == null:
		_info.text = "Не удалось создать сцену комнаты %s (корень не Node3D)." % e["id"]
		return
	_stage.add_child(_room)
	_build_table(cfg)
	_apply_toggles()
	_info.text = _info_text(e)
	_fit()


func _clear_room() -> void:
	_current_id = &""
	if _room != null:
		_stage.remove_child(_room)
		_room.queue_free()
		_room = null
	if _table != null:
		_stage.remove_child(_table)
		_table.queue_free()
		_table = null


## Столешница подмакетника: масштаб и уровень y = 0. Сцена комнаты стол не содержит, его строит RoomBuilder
func _build_table(cfg: RoomConfig) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cfg.table_top.x, cfg.table_top_thickness, cfg.table_top.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.5, 0.38)
	mesh.material = mat
	_table = MeshInstance3D.new()
	_table.name = "TableRef"
	_table.mesh = mesh
	_table.position = Vector3(0.0, -cfg.table_top_thickness * 0.5, 0.0)
	_stage.add_child(_table)


## Потолок и стол по галочкам. Потолок это ребёнок Ceiling у RoomRoot, у чужого корня потолка нет
func _apply_toggles() -> void:
	if _table != null:
		_table.visible = _table_check.button_pressed
	var rr := _room as RoomRoot
	if rr == null:
		return
	var c := rr.get_ceiling()
	if c != null:
		c.visible = _ceiling_check.button_pressed


func _info_text(e: Dictionary) -> String:
	var cfg: RoomConfig = e["cfg"]
	var lines := PackedStringArray()
	lines.append("%s" % e["title"])
	lines.append("id: %s" % e["id"])
	if String(e["tip"]) != "":
		lines.append(String(e["tip"]))
	lines.append("")
	lines.append("Размер, см: %.0f × %.0f × %.0f" % [cfg.size.x, cfg.size.y, cfg.size.z])
	lines.append("Уровень пола (floor_y): %.0f" % cfg.floor_y)
	lines.append("Форма: %s" % cfg.shape)
	lines.append("Мебель: %s" % ("да" if cfg.furnished else "нет"))
	lines.append("Дневной свет: %s" % ("да" if cfg.daylight else "нет"))
	lines.append("Ambient ×: %.2f" % cfg.ambient_mul)
	lines.append("Столешница, см: %.0f × %.0f" % [cfg.table_top.x, cfg.table_top.y])
	lines.append("Ламп в сцене: %d" % _count_lights(_room))
	return "\n".join(lines)


func _count_lights(n: Node) -> int:
	if n == null:
		return 0
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _count_lights(ch)
	return c


# ==========================================
# КАМЕРА
# ==========================================

## Границы сцены по мешам (в мировых координатах просмотра); без мешей берём размер из паспорта
func _room_bounds() -> AABB:
	var out := AABB()
	var have := false
	if _room != null:
		for mi in _meshes(_room):
			var b: AABB = mi.global_transform * mi.get_aabb()
			if have:
				out = out.merge(b)
			else:
				out = b
				have = true
	if _table != null and _table.visible:
		var tb: AABB = _table.global_transform * _table.get_aabb()
		out = out.merge(tb) if have else tb
		have = true
	if not have:
		out = AABB(Vector3(-200, -50, -150), Vector3(400, 250, 300))
	return out


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _fit() -> void:
	var box := _room_bounds()
	_pivot = box.get_center()
	var radius := maxf(box.size.length() * 0.5, 1.0)
	_dist = clampf(radius / sin(deg_to_rad(FOV) * 0.5) * 1.05, DIST_MIN, DIST_MAX)
	_update_camera()


func _update_camera() -> void:
	if _cam == null:
		return
	var p := deg_to_rad(_pitch)
	var y := deg_to_rad(_yaw)
	var dir := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(_pivot + dir * _dist, _pivot, Vector3.UP)


func _on_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_dist = clampf(_dist / ZOOM_STEP, DIST_MIN, DIST_MAX)
				MOUSE_BUTTON_WHEEL_DOWN:
					_dist = clampf(_dist * ZOOM_STEP, DIST_MIN, DIST_MAX)
				_:
					_drag_button = mb.button_index
		elif mb.button_index == _drag_button:
			_drag_button = 0
		_update_camera()
		return
	var mm := event as InputEventMouseMotion
	if mm == null or _drag_button == 0:
		return
	var pan := _drag_button == MOUSE_BUTTON_MIDDLE or _drag_button == MOUSE_BUTTON_RIGHT \
			or (_drag_button == MOUSE_BUTTON_LEFT and mm.shift_pressed)
	if pan:
		# Пиксели экрана в сантиметры мира на расстоянии до точки обзора
		var k := 2.0 * _dist * tan(deg_to_rad(FOV) * 0.5) / maxf(float(_vp.size.y), 1.0)
		var basis := _cam.global_transform.basis
		_pivot += (-basis.x * mm.relative.x + basis.y * mm.relative.y) * k
	elif _drag_button == MOUSE_BUTTON_LEFT:
		_yaw -= mm.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch + mm.relative.y * ORBIT_SPEED, -PITCH_LIMIT, PITCH_LIMIT)
	_update_camera()
