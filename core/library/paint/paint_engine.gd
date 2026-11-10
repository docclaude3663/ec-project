class_name PaintEngine extends Node

# XX claude-library (новый файл)
########################
## PaintEngine. Движок кисти: слой краски по UV2 и штампы по 3D-позиции (ATTN_22 §22.7.2.1, шаг C2.1)
########################
## Слой краски это SubViewport (RGBA8, UV2 меша), в который штампы дорисовываются шейдером stamp.gdshader
## (накопление: clear ONCE, blend_mix). Позиция и нормаль каждого текселя берутся из карты позиций (PaintBake).
## Ластик: stamp_erase.gdshader (blend_mul). Отмена и повтор: снимки слоя (сжатые FastLZ), возврат через copy.gdshader.
## Слой хранит премультиплицированный цвет в sRGB (так 2D пишет в пустой буфер): см. overlay.gdshader.
## Прототип C2.0 подтвердил: накопление, набор краски, цена прохода 32 штампов (0.6 мс GPU на 512, 1.8 мс на 1024),
## снимок для отмены (чтение 18-22 мс, 4-18 КБ после сжатия).
## Узел должен стоять в дереве до setup(): нужны SubViewport и кадры. Карта позиций строится в рабочем потоке.

signal changed          ## слой изменился (штамп, отмена, повтор, очистка)

const MAX_STAMPS := 32
const HISTORY_LIMIT := 30
const DEFAULT_RES := 1024
const STAMP_SHADER := preload("res://core/library/paint/stamp.gdshader")
const ERASE_SHADER := preload("res://core/library/paint/stamp_erase.gdshader")
const COPY_SHADER := preload("res://core/library/paint/copy.gdshader")
const OVERLAY_SHADER := preload("res://core/library/paint/overlay.gdshader")

var res := DEFAULT_RES
var target: MeshInstance3D
## Наибольший габарит меша (локальные единицы): радиус кисти задаётся долей от него
var size_ref := 1.0
var is_built := false
var bake_info: Dictionary = {}
var texture: Texture2D:
	get:
		return _vp.get_texture() if _vp != null else null

var _tri: TriangleMesh
var _vp: SubViewport
var _rect: ColorRect
var _stamp_mat: ShaderMaterial
var _erase_mat: ShaderMaterial
var _copy_mat: ShaderMaterial
var _surfaces: Array = []
var _bake_result: Dictionary = {}
var _queue: Array = []              # [{p, n, color, flow, hardness, erase}]
var _stroke_open := false
var _dirty := false
var _idle_frames := 0
var _restoring := false
var _history: Array = []            # сжатые снимки RGBA8
var _hist_index := 0
var _raw_size := 0


## Меш с UV2 у всех поверхностей, самый крупный по числу вершин; null, если такого нет
static func pick_target(meshes: Array) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := 0
	for m in meshes:
		if not (m is MeshInstance3D) or not is_instance_valid(m):
			continue
		var mi := m as MeshInstance3D
		if not PaintBake.has_uv2(mi.mesh):
			continue
		var verts := 0
		for si in mi.mesh.get_surface_count():
			verts += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if verts > best_n:
			best = mi
			best_n = verts
	return best


## Строит карту позиций (в потоке) и слой. false: нет UV2 или карта пустая. Узел уже в дереве
func setup(mi: MeshInstance3D, p_res: int = DEFAULT_RES) -> bool:
	target = mi
	res = p_res
	var mesh := mi.mesh
	if mesh == null or not PaintBake.has_uv2(mesh):
		return false
	_tri = mesh.generate_triangle_mesh()
	var aabb := mesh.get_aabb()
	size_ref = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_surfaces = PaintBake.collect(mesh)
	var id := WorkerThreadPool.add_task(_bake_job, false, "Library: карта кисти")
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	bake_info = _bake_result
	_surfaces = []
	if not bake_info.get("ok", false):
		return false
	_build_viewport()
	await _settle()
	_history = [_compress_layer()]
	_hist_index = 0
	is_built = true
	return true


func _bake_job() -> void:
	_bake_result = PaintBake.bake(_surfaces, res)


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(res, res)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var pos_img := Image.create_from_data(res, res, false, Image.FORMAT_RGBAF, (bake_info["pos"] as PackedFloat32Array).to_byte_array())
	var nrm_img := Image.create_from_data(res, res, false, Image.FORMAT_RGBAF, (bake_info["nrm"] as PackedFloat32Array).to_byte_array())
	var pos_tex := ImageTexture.create_from_image(pos_img)
	var nrm_tex := ImageTexture.create_from_image(nrm_img)
	bake_info.erase("pos")
	bake_info.erase("nrm")
	_stamp_mat = _make_stamp_material(STAMP_SHADER, pos_tex, nrm_tex)
	_erase_mat = _make_stamp_material(ERASE_SHADER, pos_tex, nrm_tex)
	_copy_mat = ShaderMaterial.new()
	_copy_mat.shader = COPY_SHADER
	_rect = ColorRect.new()
	_rect.size = Vector2(res, res)
	_rect.color = Color.WHITE
	_rect.material = _stamp_mat
	_vp.add_child(_rect)


func _make_stamp_material(shader: Shader, pos_tex: Texture2D, nrm_tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("pos_tex", pos_tex)
	m.set_shader_parameter("nrm_tex", nrm_tex)
	m.set_shader_parameter("stamp_count", 0)
	return m


## Материал накладки с этим слоем (на каждую поверхность делается копия: у каждой своя цепочка next_pass)
func make_overlay() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OVERLAY_SHADER
	m.set_shader_parameter("layer", texture)
	return m


# ==========================================
# ПОПАДАНИЕ И ШТАМПЫ
# ==========================================

## Луч камеры в точку мыши: {position, normal} в локальных координатах меша или {}
func raycast(camera: Camera3D, mouse: Vector2) -> Dictionary:
	if _tri == null or target == null or not is_instance_valid(target):
		return {}
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var inv := target.global_transform.affine_inverse()
	return _tri.intersect_ray(inv * from, (inv.basis * dir).normalized())


## Радиус кисти в локальных единицах меша по доле наибольшего габарита
func radius_for(size_frac: float) -> float:
	return size_ref * size_frac


func begin_stroke() -> void:
	_stroke_open = true


func end_stroke() -> void:
	_stroke_open = false


## Поставить штамп в очередь (рисуется в ближайшем кадре, до 32 штампов с одинаковыми параметрами за проход)
func stamp(local_pos: Vector3, local_normal: Vector3, radius: float, color: Color, flow: float, hardness: float, erase := false) -> void:
	if not is_built:
		return
	_queue.append({
		"p": Vector4(local_pos.x, local_pos.y, local_pos.z, radius),
		"n": Vector4(local_normal.x, local_normal.y, local_normal.z, 0.0),
		"color": color, "flow": flow, "hardness": hardness, "erase": erase,
	})


func has_pending() -> bool:
	return not _queue.is_empty() or _stroke_open or _dirty or _restoring


func _process(_delta: float) -> void:
	if not is_built or _restoring:
		return
	_flush()
	if _dirty and _queue.is_empty() and not _stroke_open:
		_idle_frames += 1
		if _idle_frames >= 2:
			_push_history()


func _flush() -> void:
	if _queue.is_empty():
		return
	var first: Dictionary = _queue[0]
	var mat := _erase_mat if first["erase"] else _stamp_mat
	var count := 0
	for q in _queue:
		if count >= MAX_STAMPS or not _same_params(q, first):
			break
		count += 1
	var centers: Array = []
	var normals: Array = []
	for i in MAX_STAMPS:
		if i < count:
			centers.append(_queue[i]["p"])
			normals.append(_queue[i]["n"])
		else:
			centers.append(Vector4.ZERO)
			normals.append(Vector4(0, 1, 0, 0))
	mat.set_shader_parameter("stamps", centers)
	mat.set_shader_parameter("stamp_nrm", normals)
	mat.set_shader_parameter("stamp_count", count)
	mat.set_shader_parameter("brush_color", first["color"])
	mat.set_shader_parameter("flow", first["flow"])
	mat.set_shader_parameter("hardness", first["hardness"])
	_rect.material = mat
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_queue = _queue.slice(count)
	_dirty = true
	_idle_frames = 0
	changed.emit()


func _same_params(a: Dictionary, b: Dictionary) -> bool:
	return a["erase"] == b["erase"] and a["flow"] == b["flow"] and a["hardness"] == b["hardness"] and a["color"] == b["color"]


# ==========================================
# ИСТОРИЯ
# ==========================================

func can_undo() -> bool:
	return _hist_index > 0


func can_redo() -> bool:
	return _hist_index < _history.size() - 1


## Шаг назад. false: нечего отменять или идёт штрих
func undo() -> bool:
	if not _prepare_history_step():
		return false
	if _hist_index <= 0:
		return false
	_hist_index -= 1
	_restore(_history[_hist_index])
	return true


func redo() -> bool:
	if not _prepare_history_step():
		return false
	if _hist_index >= _history.size() - 1:
		return false
	_hist_index += 1
	_restore(_history[_hist_index])
	return true


## Снимок текущего состояния, если есть несохранённые штампы. false: идёт штрих, ждём очередь или копирование
func _prepare_history_step() -> bool:
	if not is_built or _stroke_open or _restoring or not _queue.is_empty():
		return false
	if _dirty:
		_push_history()
	return true


## Очистить слой. Это тоже шаг истории
func clear() -> void:
	if not is_built:
		return
	_queue.clear()
	var blank := Image.create(res, res, false, Image.FORMAT_RGBA8)
	_copy_image(blank)
	_dirty = true
	_idle_frames = 2


func _push_history() -> void:
	_history.resize(_hist_index + 1)
	_history.append(_compress_layer())
	_hist_index = _history.size() - 1
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()
		_hist_index -= 1
	_dirty = false
	_idle_frames = 0


func _compress_layer() -> PackedByteArray:
	var raw := read_layer().get_data()
	_raw_size = raw.size()
	return raw.compress(FileAccess.COMPRESSION_FASTLZ)


func _restore(packed: PackedByteArray) -> void:
	var raw := packed.decompress(_raw_size, FileAccess.COMPRESSION_FASTLZ)
	_copy_image(Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, raw))


## Копирует картинку в слой без смешивания (два кадра: отрисовка и возврат штампа)
func _copy_image(img: Image) -> void:
	_restoring = true
	_copy_mat.set_shader_parameter("src", ImageTexture.create_from_image(img))
	_rect.material = _copy_mat
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	_rect.material = _stamp_mat
	_restoring = false
	changed.emit()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## Текущее содержимое слоя (RGBA8, премультиплицированный цвет). Читает с GPU: десятки миллисекунд
func read_layer() -> Image:
	var img := _vp.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img
