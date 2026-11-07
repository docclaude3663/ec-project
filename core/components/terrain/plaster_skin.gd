class_name PlasterSkin extends Node3D

# XX claude-terra 13.5 G2 (новый файл)
###################################
## Оболочка гипсового бинта (ATTN_13 §13.5). Один узел на весь макет, живёт в TGM (autoload).
###################################
## Для листов с C_TerrainLayer.smooth > 0 строит гладкую поверхность поверх ступеней: высоты ступеней с мировой сетки
## (cell = terrain_grid_step * CELL_K), затем PlasterField.smooth (пандусы, предел подъёма, закрепление у траков).
## Оболочка всегда не ниже ступеней, поэтому ступени, TGM, опоры, вода и D6 её не замечают.
## Меш рисуется только там, где оболочка выше ступеней (иначе мерцание вровень с верхом листа), материал по стадии листа.
## Коллизия на отдельном слое plaster: его видят только лучи постановки декора и зданий (EntitySetting.get_pick_layers).
## Лучи листов и траков оболочку не видят, иначе высота ступени округлялась бы вверх на склоне.
## Пересчёт по terrain_changed и при смене силы или стадии, не чаще раза в DELAY.

## Ячейка поля относительно шага сетки листов
const CELL_K := 0.5
## Наибольшее число ячеек поля (стол 200 x 100 при ячейке 0,5 даёт 80000)
const MAX_CELLS := 250000
const DELAY := 0.15
## Трак считается стоящим на ступени, если низ его балласта не дальше этого числа слоёв от верха ступени
const PIN_TOL_LAYERS := 1.5

var has_content := false
## Область оболочки в мире (XZ), для отсева лишних пересчётов
var region := Rect2()

var _mi: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _pending := false


func _ready() -> void:
	name = "PlasterSkin"
	_mi = MeshInstance3D.new()
	_mi.name = "Mesh"
	add_child(_mi)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = Global.active_layers(['plaster'])
	_body.collision_mask = 0
	add_child(_body)


## Пересчитать через DELAY (повторные запросы склеиваются)
func request() -> void:
	if _pending or not is_inside_tree():
		return
	_pending = true
	get_tree().create_timer(DELAY).timeout.connect(_on_delay)


func _on_delay() -> void:
	if _pending:
		rebuild()


func clear() -> void:
	_pending = false
	has_content = false
	region = Rect2()
	if _mi:
		_mi.mesh = null
	if is_instance_valid(_shape):
		_shape.queue_free()
	_shape = null


func rebuild() -> void:
	_pending = false
	var all: Array[C_TerrainLayer] = []
	var smooth_sheets: Array[C_TerrainLayer] = []
	for e in TGM.get_layers():
		var l := e.get_comp(C_TerrainLayer) as C_TerrainLayer
		if l == null:
			continue
		all.append(l)
		if l.smooth > 0:
			smooth_sheets.append(l)
	if smooth_sheets.is_empty():
		clear()
		return

	var gs = Global.settings
	var T: float = gs.layer_height
	var c: float = float(gs.terrain_grid_step) * CELL_K

	# 1. зоны: контур листа и контур, раздутый на ширину пандуса
	var zones: Array[Dictionary] = []
	var box := Rect2()
	var first := true
	for l in smooth_sheets:
		var inner := l.world_polygon()
		if inner.size() < 3:
			continue
		var run := float(l.smooth)
		var outer: Array[PackedVector2Array] = []
		for p: PackedVector2Array in Geometry2D.offset_polygon(inner, run, Geometry2D.JOIN_ROUND):
			outer.append(p)
		zones.append({"layer": l, "inner": inner, "outer": outer, "run": run, "stage": l.stage})
		var b := C_Contour.bounds_of(inner).grow(run + 1.0)
		box = b if first else box.merge(b)
		first = false
	if zones.is_empty():
		clear()
		return

	var i0 := floori(box.position.x / c)
	var j0 := floori(box.position.y / c)
	var w := ceili(box.end.x / c) - i0
	var d := ceili(box.end.y / c) - j0
	if w < 2 or d < 2 or w * d > MAX_CELLS:
		push_warning("[PlasterSkin] поле %d x %d ячеек вне допустимого, оболочка не построена" % [w, d])
		clear()
		return
	var origin := Vector2(float(i0) * c, float(j0) * c)
	region = box

	# 2. высоты ступеней: верх самого высокого твёрдого участка над центром ячейки
	var hh := PackedFloat32Array()
	hh.resize(w * d)
	for l in all:
		var lb := C_Contour.bounds_of(l.world_polygon())
		if lb.size == Vector2.ZERO or not lb.intersects(box):
			continue
		var x0 := maxi(0, floori(lb.position.x / c) - i0)
		var x1 := mini(w - 1, ceili(lb.end.x / c) - i0)
		var z0 := maxi(0, floori(lb.position.y / c) - j0)
		var z1 := mini(d - 1, ceili(lb.end.y / c) - j0)
		for j in range(z0, z1 + 1):
			for i in range(x0, x1 + 1):
				var p := origin + Vector2((float(i) + 0.5) * c, (float(j) + 0.5) * c)
				if not lb.has_point(p):
					continue
				for iv: Vector2 in l.solid_intervals_at(p):
					if iv.y > hh[j * w + i]:
						hh[j * w + i] = iv.y

	# 3. кому принадлежит ячейка: сначала лист под ней, потом тот, чей пандус сюда дотягивается
	var own := PackedInt32Array()
	own.resize(w * d)
	own.fill(-1)
	for pass_n in 2:
		for zi in zones.size():
			var polys: Array[PackedVector2Array] = []
			if pass_n == 0:
				polys.append(zones[zi]["inner"])
			else:
				polys.assign(zones[zi]["outer"])
			for poly in polys:
				var pb := C_Contour.bounds_of(poly)
				var x0 := maxi(0, floori(pb.position.x / c) - i0)
				var x1 := mini(w - 1, ceili(pb.end.x / c) - i0)
				var z0 := maxi(0, floori(pb.position.y / c) - j0)
				var z1 := mini(d - 1, ceili(pb.end.y / c) - j0)
				for j in range(z0, z1 + 1):
					for i in range(x0, x1 + 1):
						if own[j * w + i] >= 0:
							continue
						var p := origin + Vector2((float(i) + 0.5) * c, (float(j) + 0.5) * c)
						if Geometry2D.is_point_in_polygon(p, poly):
							own[j * w + i] = zi
	var run_arr := PackedFloat32Array()
	run_arr.resize(w * d)
	for k in w * d:
		if own[k] >= 0:
			run_arr[k] = zones[own[k]]["run"]

	# 4. ложе траков: оболочка там не поднимается над ступенью
	var pin := _track_pin(origin, c, w, d, hh, box, T)
	var f := PlasterField.pin_factor(pin, w, d, 2)

	# 5. оболочка
	var max_up: float = float(gs.plaster_max_up) * T
	var sk := PlasterField.smooth(hh, run_arr, f, w, d, c, T, max_up)
	_build_mesh(sk, hh, own, zones, origin, c, w, d)


## Ячейки под траками (балласт и зазор), где низ балласта стоит на ступени
func _track_pin(origin: Vector2, c: float, w: int, d: int, hh: PackedFloat32Array, box: Rect2, T: float) -> PackedByteArray:
	var pin := PackedByteArray()
	pin.resize(w * d)
	var pad: float = float(Global.settings.plaster_pin_margin) + float(Global.settings.terrain_cut_margin)
	for t in TGM.get_tracks():
		var path := t.get_comp(C_Path) as C_Path
		if path == null:
			continue
		var s := path.ballast_samples()
		for k in range(s.size() - 1):
			var a: Dictionary = s[k]
			var b: Dictionary = s[k + 1]
			var la: Vector2 = a["l"]
			var ra: Vector2 = a["r"]
			var lb: Vector2 = b["l"]
			var rb: Vector2 = b["r"]
			var da := (la - ra).normalized()
			var db := (lb - rb).normalized()
			var quad := PackedVector2Array([la + da * pad, lb + db * pad, rb - db * pad, ra - da * pad])
			var qb := C_Contour.bounds_of(quad)
			if not qb.intersects(box):
				continue
			var y_bottom := (float(a["y"]) + float(b["y"])) * 0.5
			var x0 := maxi(0, floori(qb.position.x / c) - int(floor(origin.x / c)))
			var x1 := mini(w - 1, ceili(qb.end.x / c) - int(floor(origin.x / c)))
			var z0 := maxi(0, floori(qb.position.y / c) - int(floor(origin.y / c)))
			var z1 := mini(d - 1, ceili(qb.end.y / c) - int(floor(origin.y / c)))
			for j in range(z0, z1 + 1):
				for i in range(x0, x1 + 1):
					if absf(y_bottom - hh[j * w + i]) > PIN_TOL_LAYERS * T:
						continue
					var p := origin + Vector2((float(i) + 0.5) * c, (float(j) + 0.5) * c)
					if Geometry2D.is_point_in_polygon(p, quad):
						pin[j * w + i] = 1
	return pin


func _build_mesh(sk: PackedFloat32Array, hh: PackedFloat32Array, own: PackedInt32Array, zones: Array[Dictionary],
		origin: Vector2, c: float, w: int, d: int) -> void:
	var tools := {}   # стадия -> SurfaceTool
	var counts := {}
	var eps := PlasterField.MIN_RAISE
	for j in d - 1:
		for i in w - 1:
			var a := j * w + i
			var tris := [[a, a + 1, a + w + 1], [a, a + w + 1, a + w]]
			for tri in tris:
				var owner_idx := -1
				for v: int in tri:
					if sk[v] - hh[v] > eps:
						owner_idx = own[v]
						break
				if owner_idx < 0:
					continue
				var zone: Dictionary = zones[owner_idx]
				var stage: int = zone["stage"]
				if not tools.has(stage):
					var fresh := SurfaceTool.new()
					fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
					var zl: C_TerrainLayer = zone["layer"]
					var style := zl.style if zl.style != null else TerrainStyle.new()
					fresh.set_material(style.get_top(stage))
					tools[stage] = fresh
					counts[stage] = 0
				var st: SurfaceTool = tools[stage]
				for v: int in tri:
					var vi := v % w
					@warning_ignore("integer_division")   # v / w: номер строки сетки, дробная часть не нужна
					var vj := v / w
					st.set_normal(PlasterField.normal(sk, w, d, vi, vj, c))
					st.add_vertex(Vector3(origin.x + (float(vi) + 0.5) * c, sk[v], origin.y + (float(vj) + 0.5) * c))
				counts[stage] += 1
	if tools.is_empty():
		clear()
		region = Rect2()
		return
	var mesh := ArrayMesh.new()
	for stage in tools:
		(tools[stage] as SurfaceTool).commit(mesh)
	_mi.mesh = mesh
	if is_instance_valid(_shape):
		_shape.queue_free()
	_shape = CollisionShape3D.new()
	_shape.shape = mesh.create_trimesh_shape()
	_body.add_child(_shape)
	has_content = true
