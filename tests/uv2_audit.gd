@tool
extends EditorScript

# XX claude-library (новый файл)
## Проверка UV2 у моделей для кисти Library (ATTN_22 §22.7.2.1): есть ли вторая развёртка и не перекрывается ли она.
## Запуск: открыть файл в редакторе скриптов, File, Run (Ctrl+Shift+X). Только чтение: ничего не меняет и не сохраняет.
## Для каждой сцены объектов train и building печатает по каждому видимому мешу: число поверхностей, у скольких есть UV2,
## заполнение атласа, долю перекрытых ячеек, выход за 0..1 и вердикт. Перекрытия находятся растеризацией треугольников UV2
## в сетку GRID x GRID: ячейка, центр которой попал внутрь двух разных треугольников, считается перекрытой.
## Скрытые узлы (отладочные sphere, FrontMarker, Ax, Ay, Az) пропускаются вместе с потомками.

const GRID := 512
const CATEGORIES: Array[StringName] = [&"train", &"building"]
## Папки объектов. Свой список, а не Global.object_dirs: в редакторе автолоад Global не работает (так же сделан catalog_lint)
const DIRS := [
	"res://data/trains/objects/",
	"res://data/buildings/objects/",
]
## Доля перекрытых ячеек, допустимая как погрешность растеризации
const OVERLAP_LIMIT := 0.005
const BOUNDS_EPS := 0.001


func _run() -> void:
	var checked := 0
	var flagged := 0
	var done := {}   # путь сцены -> true: одну сцену не проверяем дважды
	var settings: Array[EntitySetting] = []
	for dir in DIRS:
		for path in EntityCatalogProvider.list_resources(dir):
			var res := load(path) as EntitySetting
			if res != null:
				settings.append(res)
	for s in settings:
		if not CATEGORIES.has(s.category):
			continue
		var packed := _scene_of(s)
		if packed == null:
			print("%s: сцена модели не найдена" % s.get_key())
			continue
		if done.has(packed.resource_path):
			continue
		done[packed.resource_path] = true
		print("== %s  (%s)" % [s.get_key(), packed.resource_path])
		var root := packed.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect(root, meshes)
		if meshes.is_empty():
			print("   видимых мешей нет")
		for mi in meshes:
			checked += 1
			if not _report(mi):
				flagged += 1
		root.free()
	print("UV2: проверено мешей %d, с замечаниями %d" % [checked, flagged])


func _scene_of(setting: EntitySetting) -> PackedScene:
	for cs in setting.components:
		var sc: Variant = cs.get("scene")
		if sc is PackedScene:
			return sc
		var ident := cs as IdentitySetting
		if ident != null and ident.object_config != null:
			var sc2: Variant = ident.object_config.get("scene")
			if sc2 is PackedScene:
				return sc2
	return null


## Видимые MeshInstance3D; скрытый узел пропускается вместе с потомками
func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## false: у меша есть замечание
func _report(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh
	var surfaces := mesh.get_surface_count()
	var with_uv2 := 0
	var tris := 0
	var degenerate := 0
	var area := 0.0
	var umin := Vector2(INF, INF)
	var umax := Vector2(-INF, -INF)
	var grid := PackedInt32Array()
	grid.resize(GRID * GRID)
	grid.fill(-1)
	var covered := 0
	var overlapped := 0
	var tri_id := 0

	for si in surfaces:
		var arrays := mesh.surface_get_arrays(si)
		var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		if not (uv2 is PackedVector2Array) or (uv2 as PackedVector2Array).is_empty():
			continue
		with_uv2 += 1
		var uvs: PackedVector2Array = uv2
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var order: PackedInt32Array
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			order = idx
		else:
			order = PackedInt32Array(range(uvs.size()))
		for t in range(0, order.size() - 2, 3):
			var a := uvs[order[t]]
			var b := uvs[order[t + 1]]
			var c := uvs[order[t + 2]]
			for p in [a, b, c]:
				umin = umin.min(p)
				umax = umax.max(p)
			var tri_area := absf((b - a).cross(c - a)) * 0.5
			tris += 1
			if tri_area < 1e-12:
				degenerate += 1
				continue
			area += tri_area
			var r := _rasterize(grid, a, b, c, tri_id)
			covered += r.x
			overlapped += r.y
			tri_id += 1

	var hint := "-"
	if mesh is ArrayMesh:
		hint = str((mesh as ArrayMesh).lightmap_size_hint)
	var verdict: PackedStringArray = []
	if with_uv2 == 0:
		verdict.append("НЕТ UV2")
	else:
		if with_uv2 < surfaces:
			verdict.append("UV2 только у %d из %d поверхностей" % [with_uv2, surfaces])
		if umin.x < -BOUNDS_EPS or umin.y < -BOUNDS_EPS or umax.x > 1.0 + BOUNDS_EPS or umax.y > 1.0 + BOUNDS_EPS:
			verdict.append("выходит за 0..1")
		var ratio := float(overlapped) / float(maxi(covered, 1))
		if ratio > OVERLAP_LIMIT:
			verdict.append("ПЕРЕКРЫТИЕ %.1f%%" % (ratio * 100.0))
	var ok := verdict.is_empty()
	if with_uv2 > 0:
		print("   %s: поверхностей %d, UV2 у %d, треугольников %d (вырожденных %d), заполнение %.0f%%, перекрытие %.2f%%, границы (%.2f, %.2f)-(%.2f, %.2f), lightmap_size_hint %s  ->  %s" % [
			mi.name, surfaces, with_uv2, tris, degenerate,
			100.0 * covered / float(GRID * GRID), 100.0 * overlapped / float(maxi(covered, 1)),
			umin.x, umin.y, umax.x, umax.y, hint, "OK" if ok else "; ".join(verdict)])
	else:
		print("   %s: поверхностей %d, lightmap_size_hint %s  ->  %s" % [mi.name, surfaces, hint, "; ".join(verdict)])
	return ok


## Закрашивает в сетке ячейки, центры которых строго внутри треугольника. Возвращает (новых ячеек, перекрытых)
func _rasterize(grid: PackedInt32Array, a: Vector2, b: Vector2, c: Vector2, tri_id: int) -> Vector2i:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-18:
		return Vector2i.ZERO
	var lo := a.min(b).min(c)
	var hi := a.max(b).max(c)
	var x0 := clampi(int(floor(lo.x * GRID)), 0, GRID - 1)
	var x1 := clampi(int(ceil(hi.x * GRID)), 0, GRID - 1)
	var y0 := clampi(int(floor(lo.y * GRID)), 0, GRID - 1)
	var y1 := clampi(int(ceil(hi.y * GRID)), 0, GRID - 1)
	var added := 0
	var over := 0
	for y in range(y0, y1 + 1):
		var py := (y + 0.5) / GRID
		for x in range(x0, x1 + 1):
			var px := (x + 0.5) / GRID
			var w0 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
			var w1 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
			var w2 := 1.0 - w0 - w1
			if w0 <= 0.0 or w1 <= 0.0 or w2 <= 0.0:
				continue
			var i := y * GRID + x
			var o := grid[i]
			if o == -1:
				grid[i] = tri_id
				added += 1
			elif o != -2:
				grid[i] = -2   # перекрытая ячейка считается один раз
				over += 1
	return Vector2i(added, over)
