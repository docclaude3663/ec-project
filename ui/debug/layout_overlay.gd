class_name DebugLayoutOverlay extends Node3D

###########################
## DebugLayoutOverlay. Уровни колес, рельса и меша вокруг вагона (U14, вкладка Layout)
###########################
## Рисует поверх сцены (без теста глубины), чтобы подобрать высоту тележки и меша. Размеры колеса берутся
## с настоящего меша колеса (а не из конфига: конфиг и рельс совпадают по построению, разница всегда была бы 0):
##   желтая: поверхность катания (головка рельса под тележкой, пока тележка на рельсе);
##   синяя: низ колеса без реборды = центр оси − (радиус меша − высота реборды);
##   голубая: верх колеса с ребордой = центр оси + радиус меша;
##   фиолетовая: плоскость начала меша кузова (offset_mesh_y), тоже поперек пути.
## Подписи тележек и вагона стоят на высоте центров тележек.
## Подпись «колесо-рельс» = синяя минус желтая: 0 колесо стоит на рельсе, плюс колесо в воздухе, минус утоплено.
## Радиус меша: самая дальняя от оси вершина колеса (ось колеса это локальный X, как в C_Bogie.wheel_rotate), реборда
## входит в нее; высота реборды неизвестна из меша, ее задает панель (flange_height).
## Узел лежит в корне сцены (top_level), его создает и удаляет вкладка Layout. Если вагон удалили, узел удаляется сам.

## Допуск: до этого расхождения колесо считается стоящим на рельсе, м
const PROBLEM := 0.003
const HALF_WIDTH := 1.1
const COLOR_RAIL := Color(1.0, 0.9, 0.2)
const COLOR_TREAD := Color(0.35, 0.45, 1.0)
const COLOR_TREAD_BAD := Color(1.0, 0.3, 0.3)
const COLOR_TOP := Color(0.5, 0.95, 1.0)
const COLOR_MESH := Color(0.9, 0.4, 1.0)
const COLOR_OK := Color(0.4, 1.0, 0.5)
const LABEL_FONT_SIZE := 44

## Высота реборды над поверхностью катания, м. Задается в панели
var flange_height := 0.13

var _entity: Entity
var _imm := ImmediateMesh.new()
var _labels: Array[Label3D] = []
## Радиус колеса по мешу: instance_id колеса -> радиус (считается один раз, вершин может быть много)
var _radius_cache: Dictionary = {}


func setup(entity: Entity) -> void:
	_entity = entity
	top_level = true
	var mi := MeshInstance3D.new()
	mi.mesh = _imm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 100
	mi.material_override = mat
	add_child(mi)


func _process(_delta: float) -> void:
	if not is_instance_valid(_entity):
		queue_free()
		return
	var bc := _entity.get_comp(C_Bogie) as C_Bogie
	var vis := _entity.get_comp(C_TrainVisual) as C_TrainVisual
	if bc == null or vis == null or bc.bogies_data.is_empty():
		return
	_imm.clear_surfaces()
	_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	var label_i := 0
	var rail_sum := 0.0
	var rail_count := 0
	var top_sum := 0.0
	var top_count := 0
	var center_sum := 0.0   # высота центров тележек: на нее садятся подписи
	for data in bc.bogies_data:
		var right := data.pivot.global_basis.x.normalized()
		var on_rail := is_instance_valid(data.current_track)
		var rail_y: float = data.calculated_global_pos.y
		var base: Vector3 = data.pivot.global_position
		center_sum += base.y
		if on_rail:
			_line(Vector3(base.x, rail_y, base.z), right, COLOR_RAIL)
			rail_sum += rail_y
			rail_count += 1
		var worst := 0.0
		var has_wheel := false
		var mesh_r := 0.0
		var cfg_r := 0.0
		for w in vis.wheel_nodes:
			if w.bogie != data.id:
				continue
			var node := w.wheel_node as Node3D
			var c := node.global_position
			cfg_r = w.radius
			mesh_r = _mesh_radius(node, cfg_r + flange_height)
			var tread_low := c.y - (mesh_r - flange_height)
			var top := c.y + mesh_r
			top_sum += top
			top_count += 1
			var off := tread_low - rail_y
			var bad := on_rail and absf(off) > PROBLEM
			if not has_wheel or absf(off) > absf(worst):
				worst = off
			has_wheel = true
			_line(Vector3(c.x, tread_low, c.z), right, COLOR_TREAD_BAD if bad else COLOR_TREAD)
			_line(Vector3(c.x, top, c.z), right, COLOR_TOP)
		var text := "Bogie %d: не на рельсе" % (data.id + 1)
		var color := COLOR_OK
		if on_rail and has_wheel:
			text = "Bogie %d: колесо-рельс %+.3f" % [data.id + 1, worst]
			if absf(worst) > PROBLEM:
				color = COLOR_TREAD_BAD
		if has_wheel:
			text += "\nрадиус без реборды: меш %.3f, конфиг %.3f" % [mesh_r - flange_height, cfg_r]
		_label(label_i, text, base, color)   # на уровне центра тележки
		label_i += 1
	if not vis.mesh_nodes.is_empty():
		var m := vis.mesh_nodes[0].global_position
		_line(m, _entity.global_basis.x.normalized(), COLOR_MESH)   # поперек, как остальные
		var text := "Меш"
		if rail_count > 0:
			text += ": над рельсом %+.3f" % (m.y - rail_sum / rail_count)
		if top_count > 0:
			text += "\nнад верхом колеса %+.3f" % (m.y - top_sum / top_count)
		# Подпись вагона: над центром меша по горизонтали, по высоте на уровне центров тележек
		_label(label_i, text, Vector3(m.x, center_sum / bc.bogies_data.size(), m.z), COLOR_MESH)
		label_i += 1
	_imm.surface_end()
	for i in range(label_i, _labels.size()):
		_labels[i].hide()


## Радиус колеса по мешу: расстояние от оси (локальный X колеса) до самой дальней вершины, реборда входит в него.
## Считается один раз на колесо. Нет мешей или вершин: fallback
func _mesh_radius(wheel: Node3D, fallback: float) -> float:
	var id := wheel.get_instance_id()
	if _radius_cache.has(id):
		return _radius_cache[id]
	var meshes: Array[Node] = wheel.find_children("*", "MeshInstance3D", true, false)
	if wheel is MeshInstance3D:
		meshes.append(wheel)
	var inv := wheel.global_transform.affine_inverse()
	var r2 := 0.0
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		# В системе колеса: вращение колеса вокруг оси на результат не влияет
		var rel := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var p := rel * v
				r2 = maxf(r2, p.y * p.y + p.z * p.z)
	var r := sqrt(r2) if r2 > 0.0 else fallback
	_radius_cache[id] = r
	return r


## Горизонтальная линия поперек пути через точку center
func _line(center: Vector3, right: Vector3, color: Color) -> void:
	_imm.surface_set_color(color)
	_imm.surface_add_vertex(center - right * HALF_WIDTH)
	_imm.surface_set_color(color)
	_imm.surface_add_vertex(center + right * HALF_WIDTH)


func _label(i: int, text: String, pos: Vector3, color: Color) -> void:
	while _labels.size() <= i:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0006
		l.font_size = LABEL_FONT_SIZE
		l.outline_size = 10
		add_child(l)
		_labels.append(l)
	var lab := _labels[i]
	lab.show()
	lab.text = text
	lab.modulate = color
	lab.global_position = pos
