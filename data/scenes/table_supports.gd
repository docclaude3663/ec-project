class_name TableSupports extends RefCounted

# XX claude-table T3 (новый файл)
###################################
## Опоры подмакетника (ATTN_23 T3): ножки по контуру футпринта. Чистые функции, узлов не создаёт.
###################################
## Ножка стоит в каждом внешнем углу футпринта (объединение секций, LYM.footprint) и через каждые SPAN_MAX u на длинных рёбрах.
## Отступ центра ножки от края плиты: половина ножки + EDGE_INSET (как у стола v1: 200 x 100 даёт те же 4 ножки в углах).
## RoomBuilder строит по этому плану коробки на слое room; пересборка по LYM.layout_changed.

## Зазор от края плиты до ножки, u
const EDGE_INSET := 3.0
## Наибольший пролёт между ножками на длинном ребре, u (стол v1 200 u обходится углами)
const SPAN_MAX := 240.0
## Ножки ближе этого друг к другу считаются одной (стыки секций), u
const MERGE_DIST := 1.0


## Центры ножек (x = X, y = Z) для внешних контуров footprint. Дыры (контуры по часовой стрелке) пропускаются
static func leg_positions(footprint: Array[PackedVector2Array], leg: float) -> PackedVector2Array:
	var d := leg * 0.5 + EDGE_INSET
	var res := PackedVector2Array()
	for raw in footprint:
		if Geometry2D.is_polygon_clockwise(raw):
			continue
		var poly := _cleaned(raw)
		var n := poly.size()
		if n < 3:
			continue
		var normals: Array[Vector2] = []
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var dir := (b - a).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 0.05, poly):
				nrm = -nrm
			normals.append(nrm)
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var n_prev := normals[(i - 1 + n) % n]
			var n_cur := normals[i]
			_add_unique(res, a + (n_prev + n_cur) * d)
			var edge_len := a.distance_to(b)
			if edge_len > SPAN_MAX:
				var k := int(ceil(edge_len / SPAN_MAX)) - 1
				for j in range(1, k + 1):
					_add_unique(res, a.lerp(b, float(j) / float(k + 1)) + n_cur * d)
	return res


## Контур без повторных и лежащих на одной прямой вершин
static func _cleaned(poly: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in poly:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.001:
			pts.append(p)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.001:
		pts.remove_at(pts.size() - 1)
	var changed := true
	while changed and pts.size() >= 3:
		changed = false
		for i in pts.size():
			var a := pts[(i - 1 + pts.size()) % pts.size()]
			var b := pts[i]
			var c := pts[(i + 1) % pts.size()]
			if absf((b - a).cross(c - b)) < 0.001:
				pts.remove_at(i)
				changed = true
				break
	return pts


static func _add_unique(list: PackedVector2Array, p: Vector2) -> void:
	for q in list:
		if q.distance_to(p) < MERGE_DIST:
			return
	list.append(p)
