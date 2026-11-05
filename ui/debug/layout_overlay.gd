class_name DebugLayoutOverlay extends Node3D

###########################
## DebugLayoutOverlay. Уровни колес, рельса и меша вокруг вагона (U14, вкладка Layout)
###########################
## Рисует поверх сцены (без теста глубины), чтобы подобрать высоту тележки и меша:
##   зеленая линия: головка рельса под тележкой (только пока тележка на рельсе);
##   желтая: низ колеса, красная вместо желтой, если низ колеса не на рельсе (больше PROBLEM);
##   голубая: верх колеса;
##   фиолетовая: плоскость начала меша кузова (offset_mesh_y).
## Подписи в метрах: «колесо−рельс» (должно быть 0) и «меш над низом колеса» / «над верхом колеса».
## Узел лежит в корне сцены (top_level), его создает и удаляет вкладка Layout. Если вагон удалили, узел удаляется сам.

## Допуск: до этого расхождения колесо считается стоящим на рельсе, м
const PROBLEM := 0.003
const HALF_WIDTH := 1.1
const COLOR_RAIL := Color(0.3, 1.0, 0.4)
const COLOR_WHEEL_LOW := Color(1.0, 0.9, 0.2)
const COLOR_WHEEL_BAD := Color(1.0, 0.3, 0.3)
const COLOR_WHEEL_TOP := Color(0.3, 0.9, 1.0)
const COLOR_MESH := Color(0.9, 0.4, 1.0)

var _entity: Entity
var _imm := ImmediateMesh.new()
var _labels: Array[Label3D] = []


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
	var wheel_bottom_sum := 0.0
	var wheel_top_sum := 0.0
	var wheel_count := 0
	for data in bc.bogies_data:
		var pivot := data.pivot
		var right := pivot.global_basis.x.normalized()
		var on_rail := is_instance_valid(data.current_track)
		var rail_y: float = data.calculated_global_pos.y
		var base := pivot.global_position
		if on_rail:
			_line(Vector3(base.x, rail_y, base.z), right, COLOR_RAIL)
		var delta_text := "не на рельсе"
		var bad := false
		for w in vis.wheel_nodes:
			if w.bogie != data.id:
				continue
			var c: Vector3 = (w.wheel_node as Node3D).global_position
			var r: float = w.radius
			var low := c.y - r
			var high := c.y + r
			wheel_bottom_sum += low
			wheel_top_sum += high
			wheel_count += 1
			var off := low - rail_y
			if on_rail and absf(off) > PROBLEM:
				bad = true
			_line(Vector3(c.x, low, c.z), right, COLOR_WHEEL_BAD if (on_rail and absf(off) > PROBLEM) else COLOR_WHEEL_LOW)
			_line(Vector3(c.x, high, c.z), right, COLOR_WHEEL_TOP)
			if on_rail:
				delta_text = "колесо-рельс %+.3f" % off
		var text := "Bogie %d: %s" % [data.id + 1, delta_text]
		_label(label_i, text, base + Vector3(0.0, 1.6, 0.0), COLOR_WHEEL_BAD if bad else COLOR_RAIL)
		label_i += 1
	if not vis.mesh_nodes.is_empty() and wheel_count > 0:
		var m := vis.mesh_nodes[0].global_position
		var fwd := _entity.global_basis.z.normalized()
		var half := 2.5
		_imm.surface_set_color(COLOR_MESH)
		_imm.surface_add_vertex(m - fwd * half)
		_imm.surface_set_color(COLOR_MESH)
		_imm.surface_add_vertex(m + fwd * half)
		var low_avg := wheel_bottom_sum / wheel_count
		var high_avg := wheel_top_sum / wheel_count
		_label(label_i, "Меш: над низом колеса %+.3f, над верхом %+.3f" % [m.y - low_avg, m.y - high_avg],
				m + Vector3(0.0, 0.5, 0.0), COLOR_MESH)
		label_i += 1
	_imm.surface_end()
	for i in range(label_i, _labels.size()):
		_labels[i].hide()


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
		l.font_size = 28
		l.outline_size = 8
		add_child(l)
		_labels.append(l)
	var lab := _labels[i]
	lab.show()
	lab.text = text
	lab.modulate = color
	lab.global_position = pos
