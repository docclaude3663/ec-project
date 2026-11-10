extends Node3D

# XX claude-library (новый файл)
########################
## C2.0. Прототип кисти Library (ATTN_22 §22.7.2.1). Не часть игры: только проверка рисков до основной работы
########################
## Запуск: открыть tests/paint_spike/paint_spike.tscn и нажать F6.
## Что проверяет (всё печатается в Output, итог «C2.0: проверок n/m» и строки ИНФО):
##   1. накопление мазков в SubViewport (CLEAR_MODE_ONCE, UPDATE_ONCE): второй мазок не стирает первый;
##   2. набор краски при повторных штампах (аэрограф): альфа растёт;
##   3. карта позиций по UV2 (CPU): время, покрытие, перекрытия;
##   4. стоимость кадра штампов (GPU и CPU, мс) и чтения слоя для отмены (мс, размер после сжатия);
##   5. цвет: что реально лежит в слое (премультипликация, sRGB) и как это выглядит на модели.
## Что смотреть глазами: мерцание накладки (клавиша O: next_pass или material_overlay, Z: сдвиг по нормали),
## швы между островами UV2, соответствие цвета на модели цвету штампа (G и M переключают разбор слоя в шейдере).
##
## Управление: ЛКМ рисовать; ПКМ вращать; колесо зум; 1 сфера, 2 wagon_02, 3 loco_02_el1, 4 default_house;
## C очистить слой; Пробел сменить цвет; [ ] радиус; - = поток; H жёсткость; O режим накладки; Z сдвиг накладки;
## G sRGB-разбор; M премультипликация; T разрешение 512/1024; S автопроверки заново; P отчёт; U замер отмены.

const MAX_STAMPS := 32
const Bake := preload("res://tests/paint_spike/pos_bake.gd")
const STAMP_SHADER := preload("res://tests/paint_spike/stamp.gdshader")
const OVERLAY_SHADER := preload("res://tests/paint_spike/overlay.gdshader")

const MODELS := [
	{"name": "Сфера (UV2 создаётся в коде)", "scene": ""},
	{"name": "wagon_02", "scene": "res://data/trains/wagon_02.tscn"},
	{"name": "loco_02_el1", "scene": "res://data/trains/loco_02_el1.tscn"},
	{"name": "default_house", "scene": "res://data/buildings/default_house.tscn"},
]
const COLORS := [Color(0.9, 0.1, 0.1), Color(0.1, 0.3, 0.9), Color(0.95, 0.8, 0.1), Color(0.1, 0.7, 0.3), Color(0.95, 0.95, 0.95)]
const HARDNESS := [0.0, 0.5, 0.9]

var _res := 512
var _model_index := 0
var _model_root: Node3D
var _mi: MeshInstance3D
var _tri: TriangleMesh
var _center := Vector3.ZERO      # центр меша (локальные координаты)
var _size := 1.0                 # наибольший габарит меша
var _bake: Dictionary = {}
var _layer_vp: SubViewport
var _stamp_mat: ShaderMaterial
var _overlay_mat: ShaderMaterial
var _cam: Camera3D
var _hud: Label

var _overlay_mode := 0           # 0: next_pass на поверхностях, 1: material_overlay
var _push_on := false
var _srgb_decode := true
var _premultiplied := true
var _radius_frac := 0.06
var _flow := 0.6
var _hardness_index := 1
var _color_index := 0
var _hold_flow := 0.12           # поток при удержании на месте (аэрограф набирает краску)

var _painting := false
var _last_mouse := Vector2.ZERO
var _orbiting := false
var _yaw := 0.6
var _pitch := -0.35
var _dist := 5.0
var _stamps: Array = []          # [Vector4 центр+радиус, Vector4 нормаль]
var _stamps_total := 0
var _busy := false               # идут автопроверки: ввод мышью не рисует
var _checks_ok := 0
var _checks_all := 0
var _last_report := ""


func _ready() -> void:
	_build_environment()
	_build_hud()
	await _load_model(0)
	await _selftest()


# ==========================================
# СЦЕНА
# ==========================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(10, 8)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _update_hud() -> void:
	var b := _bake
	var bake_line := "карта позиций: нет"
	if b.has("ms"):
		bake_line = "карта позиций %dx%d: %d мс, покрыто %.0f%% (+%.0f%% dilation), перекрытий %d, треугольников %d" % [
			b["res"], b["res"], b["ms"], 100.0 * b["covered"] / float(b["res"] * b["res"]),
			100.0 * b["dilated"] / float(b["res"] * b["res"]), b["overlapped"], b["tris"]]
	_hud.text = "C2.0 прототип кисти  |  модель: %s\n%s\nЛКМ рисовать, ПКМ вращать, колесо зум. 1-4 модель, C очистить, Пробел цвет, [ ] радиус, - = поток, H жёсткость\nO накладка: %s | Z сдвиг: %s | G sRGB-разбор: %s | M премульт.: %s | T разрешение %d | S автопроверки | P отчёт | U замер отмены\nрадиус %.2f%% | поток %.2f | жёсткость %.1f | штампов %d | fps %d" % [
		MODELS[_model_index]["name"], bake_line,
		"next_pass" if _overlay_mode == 0 else "material_overlay", "вкл" if _push_on else "выкл",
		"вкл" if _srgb_decode else "выкл", "вкл" if _premultiplied else "выкл", _res,
		_radius_frac * 100.0, _flow, HARDNESS[_hardness_index], _stamps_total, Engine.get_frames_per_second()]


func _load_model(index: int) -> void:
	_busy = true
	_model_index = index
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null
	if _layer_vp != null:
		_layer_vp.queue_free()
		_layer_vp = null
	_stamps.clear()
	_model_root = Node3D.new()
	add_child(_model_root)

	var scene_path: String = MODELS[index]["scene"]
	_mi = null
	if scene_path != "":
		var packed := load(scene_path) as PackedScene
		if packed == null:
			print("ИНФО  не удалось загрузить %s, берётся сфера" % scene_path)
		else:
			var inst := packed.instantiate() as Node3D
			# корень сцены модели может быть RigidBody3D: без этого модель упадёт под действием гравитации
			inst.process_mode = Node.PROCESS_MODE_DISABLED
			_model_root.add_child(inst)
			_mi = _pick_mesh_with_uv2(inst)
			if _mi == null:
				print("ИНФО  у %s нет меша с UV2 у всех поверхностей (tests/uv2_audit.gd покажет, где), берётся сфера" % scene_path)
	if _mi == null:
		_mi = _make_sphere()
		_model_root.add_child(_mi)

	var mesh := _mi.mesh
	_tri = mesh.generate_triangle_mesh()
	var aabb := mesh.get_aabb()
	_center = aabb.get_center()
	_size = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_dist = _size * 2.2
	_update_camera()

	var t0 := Time.get_ticks_msec()
	_bake = Bake.bake(mesh, _res)
	if not _bake["ok"]:
		print("ОШИБКА  карта позиций: %s" % _bake["error"])
		_busy = false
		return
	print("ИНФО  карта позиций (%s, %dx%d): %d мс, треугольников %d, покрыто %d, dilation +%d, перекрытий %d, поверхностей без UV2: %d" % [
		MODELS[index]["name"], _res, _res, Time.get_ticks_msec() - t0, _bake["tris"], _bake["covered"], _bake["dilated"], _bake["overlapped"], _bake["skipped"]])
	_setup_layer()
	_attach_overlay()
	await get_tree().process_frame
	await get_tree().process_frame
	_busy = false


## Меш с UV2 у всех поверхностей, самый крупный по числу вершин. Скрытые узлы пропускаются
func _pick_mesh_with_uv2(root: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var ok := true
		var verts := 0
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
			if not (uv2 is PackedVector2Array) or (uv2 as PackedVector2Array).is_empty():
				ok = false
				break
			verts += (uv2 as PackedVector2Array).size()
		if ok and verts > best_n:
			best = mi
			best_n = verts
	return best


## Сфера с UV2 из lightmap_unwrap (в запуске из редактора модуль xatlas доступен)
func _make_sphere() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	mat.roughness = 0.6
	mesh.surface_set_material(0, mat)
	var err := mesh.lightmap_unwrap(Transform3D.IDENTITY, 0.05)
	print("ИНФО  lightmap_unwrap сферы: %s" % ("OK" if err == OK else "ошибка %d" % err))
	var mi := MeshInstance3D.new()
	mi.name = "Sphere"
	mi.mesh = mesh
	return mi


func _setup_layer() -> void:
	_layer_vp = SubViewport.new()
	_layer_vp.size = Vector2i(_res, _res)
	_layer_vp.transparent_bg = true
	_layer_vp.disable_3d = true
	_layer_vp.gui_disable_input = true
	# ONCE: очистить при первой отрисовке и дальше не очищать, мазки копятся
	_layer_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_layer_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_layer_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(_res, _res)
	rect.color = Color.WHITE
	_stamp_mat = ShaderMaterial.new()
	_stamp_mat.shader = STAMP_SHADER
	_stamp_mat.set_shader_parameter("pos_tex", ImageTexture.create_from_image(_bake["pos_img"]))
	_stamp_mat.set_shader_parameter("nrm_tex", ImageTexture.create_from_image(_bake["nrm_img"]))
	_stamp_mat.set_shader_parameter("stamp_count", 0)
	_apply_brush_params()
	rect.material = _stamp_mat
	_layer_vp.add_child(rect)
	RenderingServer.viewport_set_measure_render_time(_layer_vp.get_viewport_rid(), true)


func _attach_overlay() -> void:
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = OVERLAY_SHADER
	_overlay_mat.set_shader_parameter("layer", _layer_vp.get_texture())
	_apply_overlay_params()
	var mesh := _mi.mesh
	_mi.material_overlay = null
	for i in mesh.get_surface_count():
		_mi.set_surface_override_material(i, null)
	if _overlay_mode == 0:
		for i in mesh.get_surface_count():
			var base := mesh.surface_get_material(i)
			var m: BaseMaterial3D
			if base is BaseMaterial3D:
				m = (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.next_pass = _overlay_mat
			_mi.set_surface_override_material(i, m)
	else:
		_mi.material_overlay = _overlay_mat


func _apply_overlay_params() -> void:
	if _overlay_mat == null:
		return
	_overlay_mat.set_shader_parameter("premultiplied", _premultiplied)
	_overlay_mat.set_shader_parameter("srgb_decode", _srgb_decode)
	_overlay_mat.set_shader_parameter("push", _size * 0.003 if _push_on else 0.0)


func _apply_brush_params() -> void:
	if _stamp_mat == null:
		return
	_stamp_mat.set_shader_parameter("brush_color", COLORS[_color_index])
	_stamp_mat.set_shader_parameter("flow", _flow)
	_stamp_mat.set_shader_parameter("hardness", HARDNESS[_hardness_index])


# ==========================================
# ВВОД И КИСТЬ
# ==========================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed and not _busy
			_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, _size * 0.3)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = _dist * 1.1
			_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch - mm.relative.y * 0.006, -1.45, 1.45)
		_update_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		# physical_keycode: клавиши работают на любой раскладке (как в Look Lab)
		_on_key((event as InputEventKey).physical_keycode)


func _on_key(key: Key) -> void:
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4:
			if not _busy:
				_load_model(int(key - KEY_1))
		KEY_C:
			_clear_layer()
		KEY_SPACE:
			_color_index = (_color_index + 1) % COLORS.size()
			_apply_brush_params()
		KEY_BRACKETLEFT:
			_radius_frac = maxf(_radius_frac * 0.8, 0.005)
		KEY_BRACKETRIGHT:
			_radius_frac = minf(_radius_frac * 1.25, 0.4)
		KEY_MINUS:
			_flow = maxf(_flow - 0.1, 0.05)
			_apply_brush_params()
		KEY_EQUAL:
			_flow = minf(_flow + 0.1, 1.0)
			_apply_brush_params()
		KEY_H:
			_hardness_index = (_hardness_index + 1) % HARDNESS.size()
			_apply_brush_params()
		KEY_O:
			_overlay_mode = 1 - _overlay_mode
			_attach_overlay()
		KEY_Z:
			_push_on = not _push_on
			_apply_overlay_params()
		KEY_G:
			_srgb_decode = not _srgb_decode
			_apply_overlay_params()
		KEY_M:
			_premultiplied = not _premultiplied
			_apply_overlay_params()
		KEY_T:
			if not _busy:
				_res = 1024 if _res == 512 else 512
				_load_model(_model_index)
		KEY_S:
			if not _busy:
				_selftest()
		KEY_P:
			print(_last_report if _last_report != "" else "отчёта ещё нет: дождитесь автопроверок или нажмите S")
		KEY_U:
			if not _busy:
				_measure_snapshot()


func _update_camera() -> void:
	var target := _mi.global_transform * _center if _mi != null else Vector3.ZERO
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.global_position = target + dir * _dist
	_cam.look_at(target, Vector3.UP)


func _process(_delta: float) -> void:
	if _mi != null and _layer_vp != null:
		if _painting and not _busy:
			_paint_frame()
		_flush_stamps()
	_update_hud()


## Штампы за кадр: от прошлой позиции мыши к текущей по лучам (шаг около 6 пикселей); на месте один штамп в кадр
func _paint_frame() -> void:
	var mouse := get_viewport().get_mouse_position()
	var dist_px := mouse.distance_to(_last_mouse)
	var steps := clampi(int(ceil(dist_px / 6.0)), 1, 24)
	for s in steps:
		var m := _last_mouse.lerp(mouse, float(s + 1) / steps)
		var hit := _raycast(m)
		if not hit.is_empty():
			_queue_stamp(hit["position"], hit["normal"], _size * _radius_frac)
	_last_mouse = mouse


func _raycast(mouse: Vector2) -> Dictionary:
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var inv := _mi.global_transform.affine_inverse()
	return _tri.intersect_ray(inv * from, (inv.basis * dir).normalized())


func _queue_stamp(local_pos: Vector3, local_normal: Vector3, radius: float) -> void:
	_stamps.append([Vector4(local_pos.x, local_pos.y, local_pos.z, radius), Vector4(local_normal.x, local_normal.y, local_normal.z, 0.0)])


## Все накопленные штампы одним проходом (до 32 за кадр), остаток в следующий кадр
func _flush_stamps() -> void:
	if _stamps.is_empty() or _layer_vp == null:
		return
	var count := mini(_stamps.size(), MAX_STAMPS)
	var centers: Array = []
	var normals: Array = []
	for i in MAX_STAMPS:
		if i < count:
			centers.append(_stamps[i][0])
			normals.append(_stamps[i][1])
		else:
			centers.append(Vector4.ZERO)
			normals.append(Vector4(0, 1, 0, 0))
	_stamp_mat.set_shader_parameter("stamps", centers)
	_stamp_mat.set_shader_parameter("stamp_nrm", normals)
	_stamp_mat.set_shader_parameter("stamp_count", count)
	_layer_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_stamps = _stamps.slice(count)
	_stamps_total += count


func _clear_layer() -> void:
	if _layer_vp == null:
		return
	_stamps.clear()
	_stamp_mat.set_shader_parameter("stamp_count", 0)
	_layer_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_layer_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ==========================================
# АВТОПРОВЕРКИ
# ==========================================

func _check(title: String, cond: bool) -> void:
	_checks_all += 1
	if cond:
		_checks_ok += 1
		print("PASS  ", title)
	else:
		print("FAIL  ", title)


## Точка на модели: луч с стороны axis (в локальных осях меша) к центру
func _probe(axis: Vector3) -> Dictionary:
	var origin := _center + axis * _size * 3.0
	return _tri.intersect_ray(origin, -axis)


## Ждёт два кадра: штамп отрисован в SubViewport
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _stamp_now(hit: Dictionary, color: Color, radius_frac: float, flow: float) -> void:
	_stamp_mat.set_shader_parameter("brush_color", color)
	_stamp_mat.set_shader_parameter("flow", flow)
	_queue_stamp(hit["position"], hit["normal"], _size * radius_frac)
	_flush_stamps()
	await _settle()


## Читает слой: {red, blue, max_alpha, avg_red, avg_blue} (цвет после снятия премультипликации)
func _read_layer() -> Dictionary:
	var img := _layer_vp.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var red := 0
	var blue := 0
	var max_a := 0.0
	var sum_red := Color(0, 0, 0, 0)
	var sum_blue := Color(0, 0, 0, 0)
	for i in range(0, data.size(), 4):
		var a := data[i + 3] / 255.0
		if a > max_a:
			max_a = a
		if a < 0.5:
			continue
		var c := Color(data[i] / 255.0 / a, data[i + 1] / 255.0 / a, data[i + 2] / 255.0 / a)
		if c.r > c.b:
			red += 1
			sum_red += c
		else:
			blue += 1
			sum_blue += c
	var out := {"red": red, "blue": blue, "max_alpha": max_a, "avg_red": Color.BLACK, "avg_blue": Color.BLACK}
	if red > 0:
		out["avg_red"] = Color(sum_red.r / red, sum_red.g / red, sum_red.b / red)
	if blue > 0:
		out["avg_blue"] = Color(sum_blue.r / blue, sum_blue.g / blue, sum_blue.b / blue)
	return out


func _selftest() -> void:
	_busy = true
	_checks_ok = 0
	_checks_all = 0
	var lines: Array[String] = []
	print("== C2.0: автопроверки (модель: %s, слой %dx%d) ==" % [MODELS[_model_index]["name"], _res, _res])
	_check("карта позиций построена и покрывает модель (> 3% текселей)", _bake.get("ok", false) and _bake["covered"] > int(0.03 * _res * _res))

	var p_right := _probe(Vector3.RIGHT)
	var p_left := _probe(Vector3.LEFT)
	_check("лучи в две противоположные стороны модели попали в меш", not p_right.is_empty() and not p_left.is_empty())
	if p_right.is_empty() or p_left.is_empty():
		_finish_selftest(lines)
		return

	# 1. накопление: красный мазок с одной стороны, затем синий с другой
	_clear_layer()
	await _settle()
	await _stamp_now(p_right, Color(1, 0, 0), 0.12, 1.0)
	var r1 := _read_layer()
	await _stamp_now(p_left, Color(0, 0, 1), 0.12, 1.0)
	var r2 := _read_layer()
	_check("слой после красного штампа содержит краску (текселей: %d)" % r1["red"], r1["red"] > 0)
	_check("второй (синий) мазок не стёр первый: красных %d -> %d, синих %d" % [r1["red"], r2["red"], r2["blue"]], r2["red"] >= r1["red"] * 0.95 and r2["blue"] > 0)
	lines.append("ИНФО  цвет в слое после снятия премультипликации: красный %s, синий %s (ожидалось (1, 0, 0) и (0, 0, 1))" % [r2["avg_red"], r2["avg_blue"]])
	lines.append("ИНФО  если цвет в слое темнее ожидаемого, 2D пишет иначе, чем предполагает шейдер накладки: смотрите на модель с G и M")

	# 2. набор краски: два штампа с потоком 0.5 в одну точку
	_clear_layer()
	await _settle()
	await _stamp_now(p_right, Color(1, 0, 0), 0.12, 0.5)
	var a1 := float(_read_layer()["max_alpha"])
	await _stamp_now(p_right, Color(1, 0, 0), 0.12, 0.5)
	var a2 := float(_read_layer()["max_alpha"])
	_check("повторный штамп набирает краску (максимум альфы %.2f -> %.2f)" % [a1, a2], a2 > a1 + 0.1 and a1 > 0.3 and a1 < 0.7)

	# 3. стоимость штампов: 30 кадров по 32 штампа
	_clear_layer()
	await _settle()
	var gpu_sum := 0.0
	var cpu_sum := 0.0
	var vp_rid := _layer_vp.get_viewport_rid()
	for f in 30:
		for k in MAX_STAMPS:
			var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _size * 0.05
			_queue_stamp(p_right["position"] + jitter, p_right["normal"], _size * 0.03)
		_flush_stamps()
		await get_tree().process_frame
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	lines.append("ИНФО  проход штампов (32 штампа, слой %dx%d): GPU %.3f мс, CPU %.3f мс в среднем за 30 кадров" % [_res, _res, gpu_sum / 30.0, cpu_sum / 30.0])
	_check("проход штампов дешевле 4 мс на GPU (%.3f мс)" % (gpu_sum / 30.0), gpu_sum / 30.0 < 4.0)

	# 4. чтение слоя для отмены
	await _settle()
	_measure_snapshot_into(lines)

	# 5. цвет на модели: пиксель в центре кадра против цвета штампа, все четыре сочетания G и M
	await _color_test(lines)

	_finish_selftest(lines)


## Камера смотрит на точку попадания вдоль нормали; штамп цвета (0.9, 0.2, 0.1) с потоком 1; накладка без освещения
## (debug_flat). Пиксель в центре кадра должен совпасть с цветом штампа. Лучшее сочетание G и M остаётся включённым
func _color_test(lines: Array[String]) -> void:
	var hit := _probe(Vector3.RIGHT)
	if hit.is_empty():
		lines.append("ИНФО  проверка цвета пропущена: нет попадания луча")
		return
	var expected := Color(0.9, 0.2, 0.1)
	var world_pos: Vector3 = _mi.global_transform * (hit["position"] as Vector3)
	var world_n: Vector3 = ((_mi.global_transform.basis * (hit["normal"] as Vector3))).normalized()
	_cam.global_position = world_pos + world_n * _size * 1.2
	_cam.look_at(world_pos, Vector3.UP)
	_overlay_mat.set_shader_parameter("debug_flat", true)
	_clear_layer()
	await _settle()
	await _stamp_now(hit, expected, 0.15, 1.0)
	var best_err := 9.0
	var best_g := true
	var best_m := true
	for combo in [[true, true], [false, true], [true, false], [false, false]]:
		_srgb_decode = combo[0]
		_premultiplied = combo[1]
		_apply_overlay_params()
		await _settle()
		var img := get_viewport().get_texture().get_image()
		var px := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var err := maxf(absf(px.r - expected.r), maxf(absf(px.g - expected.g), absf(px.b - expected.b)))
		lines.append("ИНФО  цвет на экране при G=%s M=%s: (%.2f, %.2f, %.2f), ожидалось (%.2f, %.2f, %.2f), ошибка %.3f" % [
			"вкл" if combo[0] else "выкл", "вкл" if combo[1] else "выкл", px.r, px.g, px.b, expected.r, expected.g, expected.b, err])
		if err < best_err:
			best_err = err
			best_g = combo[0]
			best_m = combo[1]
	_srgb_decode = best_g
	_premultiplied = best_m
	_apply_overlay_params()
	_overlay_mat.set_shader_parameter("debug_flat", false)
	lines.append("ИНФО  лучшее сочетание: G=%s M=%s (оставлено включённым)" % ["вкл" if best_g else "выкл", "вкл" if best_m else "выкл"])
	_check("цвет на модели совпадает с цветом штампа (ошибка %.3f)" % best_err, best_err < 0.04)
	_update_camera()


func _measure_snapshot() -> void:
	var lines: Array[String] = []
	_measure_snapshot_into(lines)
	for l in lines:
		print(l)


func _measure_snapshot_into(lines: Array[String]) -> void:
	var t0 := Time.get_ticks_usec()
	var img := _layer_vp.get_texture().get_image()
	var t1 := Time.get_ticks_usec()
	var raw := img.get_data()
	var packed := raw.compress(FileAccess.COMPRESSION_FASTLZ)
	var t2 := Time.get_ticks_usec()
	var back := packed.decompress(raw.size(), FileAccess.COMPRESSION_FASTLZ)
	var t3 := Time.get_ticks_usec()
	lines.append("ИНФО  снимок слоя для отмены: чтение с GPU %.1f мс, сжатие FastLZ %.1f мс (%d КБ -> %d КБ), распаковка %.1f мс" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, raw.size() / 1024, packed.size() / 1024, (t3 - t2) / 1000.0])
	_check("снимок слоя читается и разворачивается без потерь", back.size() == raw.size() and back == raw)


func _finish_selftest(lines: Array[String]) -> void:
	_clear_layer()
	_apply_brush_params()   # автопроверки меняли цвет и поток штампа
	var summary := "C2.0: проверок %d/%d" % [_checks_ok, _checks_all]
	var report: Array[String] = []
	report.append_array(lines)
	report.append(summary)
	report.append("Теперь глазами: рисуйте ЛКМ, крутите ПКМ. Нужно ответить на вопросы из ATTN_22 §22.7.2.1 (мерцание, цвет, швы).")
	for l in report:
		print(l)
	_last_report = "\n".join(report)
	_busy = false
