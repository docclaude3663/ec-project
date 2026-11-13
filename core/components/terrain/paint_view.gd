class_name PaintView extends Node3D

# XX claude-terra 13.13 K2 (новый файл)
###################################
## Временная разметка краски плоскими цветами (ATTN_13 §13.13, K1+K2). Этап K3 заменит её шейдером оболочки.
###################################
## По чанку PaintMap один меш: ячейки краски это вершины (как у оболочки), цвет вершины это смесь цветов классов,
## прозрачность растёт с весом краски, поэтому края мазка мягкие. Высота вершины это оболочка + LIFT.
## Рисуется только там, где ячейка под бинтом (PlasterSkin.is_plastered_cell): снятый бинт прячет краску, не стирая её.
## Чанки пересобираются не больше REBUILD_PER_FRAME за кадр.

const LIFT := 0.03
const ALPHA := 0.8
const REBUILD_PER_FRAME := 24
const COLORS: Array[Color] = [
	Color(0.22, 0.72, 0.2),   # трава
	Color(0.5, 0.5, 0.56),    # скала
	Color(0.88, 0.74, 0.42),  # гравий
	Color(0.9, 0.95, 1.0),    # запас
]

var map: PaintMap
var skin: PlasterSkin

var _mis := {}      # Vector2i -> MeshInstance3D
var _dirty := {}    # Vector2i -> true
var _mat: StandardMaterial3D


func _ready() -> void:
	name = "PaintView"
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_process(false)
	if map != null:
		map.changed.connect(_on_changed)
	if skin != null:
		skin.rebuilt.connect(_on_skin_rebuilt)


## Чанк и три соседа (слева, сверху, по диагонали): их ячейки берут вершины из изменённого чанка
func _on_changed(keys: Array) -> void:
	for k: Vector2i in keys:
		_dirty[k] = true
		_dirty[k + Vector2i(-1, 0)] = true
		_dirty[k + Vector2i(0, -1)] = true
		_dirty[k + Vector2i(-1, -1)] = true
	set_process(true)


func _on_skin_rebuilt() -> void:
	for k in map.chunk_keys():
		_dirty[k] = true
		_dirty[k + Vector2i(-1, 0)] = true
		_dirty[k + Vector2i(0, -1)] = true
		_dirty[k + Vector2i(-1, -1)] = true
	for k in _mis.keys():
		_dirty[k] = true
	if not _dirty.is_empty():
		set_process(true)


func _process(_delta: float) -> void:
	var n := 0
	for k: Vector2i in _dirty.keys():
		_dirty.erase(k)
		_rebuild_chunk(k)
		n += 1
		if n >= REBUILD_PER_FRAME:
			break
	if _dirty.is_empty():
		set_process(false)


func _rebuild_chunk(key: Vector2i) -> void:
	var cs := PaintMap.CHUNK
	var c := map.cell
	var ox := key.x * cs
	var oz := key.y * cs
	var side := cs + 1
	var ys := PackedFloat32Array()
	ys.resize(side * side)
	var cols := PackedColorArray()
	cols.resize(side * side)
	var any := false
	for j in side:
		for i in side:
			var gi := ox + i
			var gj := oz + j
			var k := j * side + i
			cols[k] = Color(0, 0, 0, 0)
			ys[k] = skin.height_at_cell(gi, gj)
			if not skin.is_plastered_cell(gi, gj):
				continue
			var w := map.weights(gi, gj)
			var sum := w.r + w.g + w.b + w.a
			if sum <= 0.0:
				continue
			var rgb := (COLORS[0] * w.r + COLORS[1] * w.g + COLORS[2] * w.b + COLORS[3] * w.a) / sum
			cols[k] = Color(rgb.r, rgb.g, rgb.b, minf(sum, 1.0) * ALPHA)
			any = true
	var verts := PackedVector3Array()
	var vcols := PackedColorArray()
	if any:
		for j in cs:
			for i in cs:
				var a := j * side + i
				var b := a + 1
				var d := a + side
				var e := d + 1
				if cols[a].a + cols[b].a + cols[d].a + cols[e].a <= 0.0:
					continue
				if is_nan(ys[a]) or is_nan(ys[b]) or is_nan(ys[d]) or is_nan(ys[e]):
					continue
				for v: int in [a, b, e, a, e, d]:
					var vi := v % side
					@warning_ignore("integer_division")   # v / side: номер строки вершин
					var vj := v / side
					verts.append(Vector3((float(ox + vi) + 0.5) * c, ys[v] + LIFT, (float(oz + vj) + 0.5) * c))
					vcols.append(cols[v])
	var mi: MeshInstance3D = _mis.get(key)
	if verts.is_empty():
		if mi != null:
			mi.queue_free()
			_mis.erase(key)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Paint_%d_%d" % [key.x, key.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _mat
		add_child(mi)
		_mis[key] = mi
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = vcols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
