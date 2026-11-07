class_name TrackSleeperFactory extends RefCounted

########################
## Меши шпал (ATTN_20, шаг T3)
########################
## Без интерфейса. Контракт меша шпалы (ATTN_15 §2, ATTN_20 §20.3.3): origin в центре площади опоры,
## низ на y = 0, длинная сторона поперёк пути по X (там рельсы), шаг вдоль Z.
## Меши генератора одноповерхностные, UV в ю (1 единица UV = 1 ю): материал масштабирует тайл через uv1_scale.
## Площадки под рельс красятся вершинным цветом, а не вторым материалом: цена та же, что у шпалы без них.

const GENERATED_DEFAULTS := {
	"profile": "rect",         # rect: прямоугольное сечение, фаски со всех рёбер; trapezoid: низ шире верха (taper)
	"length": 3.0,             # по X, поперёк пути
	"height": 0.2,             # высота корпуса без площадок
	"width": 0.3,              # по Z, вдоль пути
	"chamfer": 0.02,           # фаска рёбер, ю (0 = без фасок)
	"taper": 0.03,             # trapezoid: на сколько верх уже низа с каждой стороны, ю
	# Площадки под рельс (на любом сечении)
	"pads": false,
	"pad_x": 0.875,            # центр площадки от оси шпалы (по умолчанию половина колеи стиля)
	"pad_length": 0.4,         # по X
	"pad_width": 0.0,          # по Z, 0 = на всю плоскую часть верха
	"pad_height": 0.02,        # над верхом корпуса
	"pad_color": Color(0.30, 0.30, 0.33),   # вершинный цвет: бесплатно, один материал и одна поверхность
	"pad_lifts_rail": true,    # true: рельс стоит на площадке; false: рельс на корпусе, площадка только деталь (костыль)
	# Рельеф (0 = не создаётся ни вершин, ни рёбер)
	"top_dip": 0.0,            # прогиб верха между площадками, ю
	"relief_slope": 0.08,      # длина скоса внутрь: от края площадки в прогиб, по X
	"end_slope": 0.0,          # высота скоса наружу: верх заваливается от края площадки до конца шпалы, ю
	# UV
	"uv_rotate": false,        # повернуть UV на 90° (волокна вдоль / поперёк)
}


# ==========================================
# Генератор
# ==========================================

## Меш шпалы по спецификации (см. GENERATED_DEFAULTS). Корпус собирается из сечений вдоль X: без рельефа это
## два сечения (концы), прогиб и скос к концам добавляют только нужные сечения. В метаданных меша:
## track_spec (как собран) и seat_height (высота постели рельса, если площадки её не поднимают)
static func generate(spec: Dictionary) -> ArrayMesh:
	var s: Dictionary = GENERATED_DEFAULTS.duplicate()
	s.merge(spec, true)
	var L := maxf(float(s["length"]), 0.05)
	var H := maxf(float(s["height"]), 0.02)
	var W := maxf(float(s["width"]), 0.02)
	var c := clampf(float(s["chamfer"]), 0.0, minf(H, W) * 0.45)
	var trapezoid: bool = s["profile"] == "trapezoid"
	var hw := W * 0.5
	var tp := clampf(float(s["taper"]), 0.0, W * 0.3) if trapezoid else 0.0
	var rot: bool = s["uv_rotate"]

	# --- рельеф: падение верха как кусочно-линейная функция вдоль X ---
	var slope := clampf(float(s["relief_slope"]), 0.005, 1.0)
	var seat_x := absf(float(s["pad_x"]))
	var seat_len := clampf(float(s["pad_length"]), 0.02, L)
	var max_drop := maxf(H - 2.0 * c - 0.01, 0.0)
	var dip := clampf(float(s["top_dip"]), 0.0, max_drop)
	var end_slope := clampf(float(s["end_slope"]), 0.0, max_drop)
	var drop_lists: Array = []      # каждый список [[x, значение], ...] по возрастанию x; падение = максимум по спискам
	if dip > 0.0:
		var x_in := seat_x - seat_len * 0.5
		if x_in > 0.02:
			var sl := minf(slope, x_in * 0.5)
			drop_lists.append([[-x_in, 0.0], [-x_in + sl, dip], [x_in - sl, dip], [x_in, 0.0]])
	if end_slope > 0.0:
		var x_out := seat_x + seat_len * 0.5
		if x_out < L * 0.5 - 0.005:
			drop_lists.append([[-L * 0.5, end_slope], [-x_out, 0.0]])
			drop_lists.append([[x_out, 0.0], [L * 0.5, end_slope]])

	# --- сечения ---
	var xs: Array[float] = [-L * 0.5, L * 0.5]
	for lst in drop_lists:
		for pt in lst:
			xs.append(clampf(pt[0], -L * 0.5, L * 0.5))
	xs.sort()
	var uniq: Array[float] = []
	for x in xs:
		if uniq.is_empty() or x - uniq[uniq.size() - 1] > 0.0005:
			uniq.append(x)
	xs = uniq

	var keep := _keep_indices(_profile_raw(hw, tp, H, c, 0.0, trapezoid))
	var slices: Array = []          # по сечению на каждый x: массив Vector2 (z, y)
	for x in xs:
		var drop := 0.0
		for lst in drop_lists:
			drop = maxf(drop, _interp(lst, x))
		var raw := _profile_raw(hw, tp, H, c, drop, trapezoid)
		var pts: Array[Vector2] = []
		for i in keep:
			pts.append(raw[i])
		slices.append(pts)

	var use_color: bool = s["pads"] and float(s["pad_height"]) > 0.001
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if use_color:
		st.set_color(Color.WHITE)

	# --- боковая поверхность между соседними сечениями ---
	for si in slices.size() - 1:
		var p0: Array = slices[si]
		var p1: Array = slices[si + 1]
		var x0: float = xs[si]
		var x1: float = xs[si + 1]
		var per0 := _perimeter(p0)
		var per1 := _perimeter(p1)
		for i in p0.size():
			var j := (i + 1) % p0.size()
			var a0 := Vector3(x0, p0[i].y, p0[i].x)
			var b0 := Vector3(x0, p0[j].y, p0[j].x)
			var a1 := Vector3(x1, p1[i].y, p1[i].x)
			var b1 := Vector3(x1, p1[j].y, p1[j].x)
			var e := b0 - a0
			if e.length_squared() < 1e-10:
				e = b1 - a1
			var expected := Vector3.RIGHT.cross(e)   # наружу для сечения против часовой
			var n := (b1 - a0).cross(b0 - a1)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			if n.dot(expected) < 0.0:
				n = -n
			var l0 = (p0[j] - p0[i]).length()
			var l1 = (p1[j] - p1[i]).length()
			TrackMeshBuilder.quad(st, [a0, a1, b1, b0], [n, n, n, n], [
				_uv(x0, per0[i], rot), _uv(x1, per1[i], rot), _uv(x1, per1[i] + l1, rot), _uv(x0, per0[i] + l0, rot)])

	# --- торцы: веер из выпуклого многоугольника ---
	for end in [0, slices.size() - 1]:
		var pts: Array = slices[end]
		var x: float = xs[end]
		var n := Vector3(-1.0 if end == 0 else 1.0, 0.0, 0.0)
		var center := Vector2.ZERO
		for v in pts:
			center += v
		center /= pts.size()
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			_tri(st, Vector3(x, center.y, center.x), Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), n,
				_uv(center.x, center.y, rot), _uv(a.x, a.y, rot), _uv(b.x, b.y, rot))

	# --- площадки ---
	var pad_h := float(s["pad_height"])
	if use_color:
		var pl := clampf(float(s["pad_length"]), 0.02, L)
		var pw := float(s["pad_width"])
		pw = minf(pw, W) if pw > 0.0 else maxf((hw - tp - c) * 2.0, 0.02)
		var px := minf(seat_x, L * 0.5 - pl * 0.5)
		st.set_color(s["pad_color"])
		for sx in [-1.0, 1.0]:
			_box(st, Vector3(sx * px - pl * 0.5, H, -pw * 0.5), Vector3(pl, pad_h, pw), rot)
		st.set_color(Color.WHITE)

	st.generate_tangents()
	var mesh := st.commit()
	mesh.set_meta("track_spec", s)
	if use_color and not bool(s["pad_lifts_rail"]):
		mesh.set_meta("seat_height", H)
	return mesh


## Сечение в плоскости (z, y), против часовой, фиксированное число точек (дубликаты убирает _keep_indices)
static func _profile_raw(hw: float, tp: float, H: float, c: float, drop: float, trapezoid: bool) -> Array[Vector2]:
	var top := H - drop
	if trapezoid:
		var ht := hw - tp
		return [Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(ht, top - c), Vector2(ht - c, top),
			Vector2(-ht + c, top), Vector2(-ht, top - c)]
	return [Vector2(-hw + c, 0.0), Vector2(hw - c, 0.0), Vector2(hw, c), Vector2(hw, top - c),
		Vector2(hw - c, top), Vector2(-hw + c, top), Vector2(-hw, top - c), Vector2(-hw, c)]


## Индексы точек без подряд идущих повторов (фаска 0 схлопывает пары точек)
static func _keep_indices(raw: Array[Vector2]) -> Array[int]:
	var out: Array[int] = []
	for i in raw.size():
		if out.is_empty() or not raw[out[out.size() - 1]].is_equal_approx(raw[i]):
			out.append(i)
	if out.size() > 1 and raw[out[0]].is_equal_approx(raw[out[out.size() - 1]]):
		out.remove_at(out.size() - 1)
	return out


## Значение кусочно-линейной функции [[x, v], ...] (по возрастанию x), на границах включительно; вне диапазона 0
static func _interp(pts: Array, x: float) -> float:
	if pts.size() < 2 or x < pts[0][0] or x > pts[pts.size() - 1][0]:
		return 0.0
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if x >= a[0] and x <= b[0]:
			var t = 0.0 if is_equal_approx(a[0], b[0]) else (x - a[0]) / (b[0] - a[0])
			return lerpf(a[1], b[1], t)
	return 0.0


## Накопленная длина вдоль замкнутой ломаной до каждой точки
static func _perimeter(p: Array) -> Array[float]:
	var out: Array[float] = []
	var acc := 0.0
	for i in p.size():
		out.append(acc)
		acc += (p[(i + 1) % p.size()] - p[i]).length()
	return out


static func _uv(u: float, v: float, rotate: bool) -> Vector2:
	return Vector2(v, u) if rotate else Vector2(u, v)


## Коробка с плоскими нормалями и UV в ю. pos = минимальный угол
static func _box(st: SurfaceTool, pos: Vector3, size: Vector3, rotate := false) -> void:
	var a := pos
	var b := pos + size
	# грани: [нормаль, 4 угла]
	var faces := [
		[Vector3.UP, Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)],
		[Vector3.DOWN, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)],
		[Vector3.RIGHT, Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z)],
		[Vector3.LEFT, Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z)],
		[Vector3.BACK, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)],
		[Vector3.FORWARD, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var pts: Array = [f[1], f[2], f[3], f[4]]
		var uvs: Array = []
		for p in pts:
			# планарная проекция по оси нормали
			if absf(n.y) > 0.5:
				uvs.append(_uv(p.x, p.z, rotate))
			elif absf(n.x) > 0.5:
				uvs.append(_uv(p.z, p.y, rotate))
			else:
				uvs.append(_uv(p.x, p.y, rotate))
		TrackMeshBuilder.quad(st, pts, [n, n, n, n], uvs)


## Треугольник; порядок вершин выбирается по ожидаемой нормали (Godot: лицевая сторона по часовой)
static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2) -> void:
	var geo := (p1 - p0).cross(p2 - p0)
	var idx := [0, 1, 2]
	if geo.dot(n) > 0.0:
		idx = [0, 2, 1]
	var ps := [p0, p1, p2]
	var uvs := [uv0, uv1, uv2]
	for k in idx:
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(ps[k])


# ==========================================
# Импорт и нормализация
# ==========================================

## Меши из ресурса: Mesh -> один элемент; PackedScene (.glb, .gltf, .tscn) -> все MeshInstance3D.
## Элемент: {name, mesh, xform} (xform относительно корня сцены)
static func load_meshes(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var res := ResourceLoader.load(path)
	if res is Mesh:
		out.append({"name": path.get_file().get_basename(), "mesh": res, "xform": Transform3D.IDENTITY})
	elif res is PackedScene:
		var root := (res as PackedScene).instantiate()
		_collect(root, Transform3D.IDENTITY, out)
		root.free()
	return out


static func _collect(node: Node, parent_xf: Transform3D, out: Array[Dictionary]) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		out.append({"name": String(mi.name), "mesh": mi.mesh, "xform": xf})
	for c in node.get_children():
		_collect(c, xf, out)


## Приводит меши к контракту. items: [{mesh, xform}], opts: scale (множитель), rotate_y (градусы),
## auto_orient (длинную сторону на X), keep_materials, merge (слить поверхности в одну).
## Возвращает {mesh: ArrayMesh, report: {...}}
@warning_ignore("integer_division")
static func normalize(items: Array, opts: Dictionary = {}) -> Dictionary:
	var o := {"scale": 1.0, "rotate_y": 0.0, "auto_orient": true, "keep_materials": true, "merge": false}
	o.merge(opts, true)
	var notes := PackedStringArray()
	var report := {"notes": notes}

	var pre := Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(float(o["rotate_y"])), 0.0)).scaled(Vector3.ONE * float(o["scale"])), Vector3.ZERO)
	var before := _bounds(items, Transform3D.IDENTITY)
	var box := _bounds(items, pre)
	report["before"] = before
	if o["auto_orient"] and box.size.x < box.size.z - 0.0001:
		pre = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * pre
		box = _bounds(items, pre)
		notes.append("длинная сторона была по Z: повёрнуто на 90° вокруг Y")
	var c := box.get_center()
	var offset := Vector3(-c.x, -box.position.y, -c.z)
	var final_xf := Transform3D(Basis.IDENTITY, offset) * pre
	if final_xf.basis.determinant() < 0.0:
		notes.append("зеркальное преобразование: лицевые стороны могут быть вывернуты")

	var mesh := ArrayMesh.new()
	var merged := {}   # ключ массива -> объединённые данные (при merge)
	var merge_ok: bool = o["merge"]
	var verts_total := 0
	for it in items:
		var src: Mesh = it["mesh"]
		var xf: Transform3D = final_xf * (it["xform"] as Transform3D)
		for s in src.get_surface_count():
			if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				notes.append("поверхность %d не из треугольников, пропущена" % s)
				continue
			var arrays := _transform_arrays(src.surface_get_arrays(s), xf)
			if merge_ok:
				_merge_into(merged, arrays, verts_total)
				verts_total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			else:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				if o["keep_materials"]:
					mesh.surface_set_material(mesh.get_surface_count() - 1, src.surface_get_material(s))
	if merge_ok:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		for k in merged:
			arrays[k] = merged[k]
		if arrays[Mesh.ARRAY_VERTEX] != null:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	report["after"] = mesh.get_aabb()
	report["surfaces"] = mesh.get_surface_count()
	@warning_ignore("integer_division")
	report["triangles"] = mesh.get_faces().size() / 3
	return {"mesh": mesh, "report": report}


## AABB всех мешей после преобразования pre * xform
static func _bounds(items: Array, pre: Transform3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for it in items:
		var t: Transform3D = pre * (it["xform"] as Transform3D)
		var a: AABB = (it["mesh"] as Mesh).get_aabb()
		for i in 8:
			var p := t * a.get_endpoint(i)
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		return AABB()
	return AABB(lo, hi - lo)


static func _transform_arrays(arrays: Array, xf: Transform3D) -> Array:
	var out := arrays.duplicate()
	var nb := xf.basis.inverse().transposed()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nv := PackedVector3Array()
	nv.resize(verts.size())
	for i in verts.size():
		nv[i] = xf * verts[i]
	out[Mesh.ARRAY_VERTEX] = nv
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var nn := PackedVector3Array()
		nn.resize(ns.size())
		for i in ns.size():
			nn[i] = (nb * ns[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = nn
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var ts: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var nt := ts.duplicate()
		for i in range(0, ts.size() - 3, 4):
			var t3 := (xf.basis * Vector3(ts[i], ts[i + 1], ts[i + 2])).normalized()
			nt[i] = t3.x
			nt[i + 1] = t3.y
			nt[i + 2] = t3.z
		out[Mesh.ARRAY_TANGENT] = nt
	return out


## Добавляет массивы поверхности в общий набор; индексы сдвигаются на offset вершин
static func _merge_into(merged: Dictionary, arrays: Array, offset: int) -> void:
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
		if arrays[k] == null:
			continue
		if not merged.has(k):
			merged[k] = arrays[k].duplicate()
		else:
			merged[k].append_array(arrays[k])
	var idx: PackedInt32Array
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	else:
		idx = PackedInt32Array()
		var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		idx.resize(n)
		for i in n:
			idx[i] = i
	for i in idx.size():
		idx[i] += offset
	if not merged.has(Mesh.ARRAY_INDEX):
		merged[Mesh.ARRAY_INDEX] = idx
	else:
		merged[Mesh.ARRAY_INDEX].append_array(idx)


## Сводка по мешу: {size, aabb, triangles, surfaces}
@warning_ignore("integer_division")
static func info(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {}
	@warning_ignore("integer_division")
	var tris := mesh.get_faces().size() / 3
	return {"aabb": mesh.get_aabb(), "size": mesh.get_aabb().size, "triangles": tris, "surfaces": mesh.get_surface_count()}


## Записывает меш в .res и привязывает к файлу (стиль будет хранить ссылку). Возвращает Error
static func save_mesh(mesh: Mesh, path: String) -> int:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(mesh, path)
	if err == OK:
		mesh.take_over_path(path)
	return err
