class_name WaterFill extends RefCounted

# XX claude-terra 13.4 W1 (новый файл)
#######################
## Ядро воды (ATTN_13 §13.4). Чистые функции без состояния, сцены и узлов нет.
#######################
## Вода это плоскость на уровне level_y (кратен layer_height) и область на сетке terrain_grid_step.
## Ячейка мокрая, если в слое воды [level_y - T, level_y) в ней нет твёрдого тела листа и она связана
## (по 4 соседям) с ячейкой точки клика. Домен (снимок стола на момент заливки) ограничивает область:
## за ним стена, а не утечка. Всё, что ниже уровня и достижимо, заливается.
## Занятость ячейки подаёт вызывающий (Callable(Vector2) -> bool): blocker_for() строит её по листам TGM,
## тест подаёт свою. Центр ячейки (i + 0,5) * шаг.

## Предохранитель области, ячеек (стол 200 x 100 при шаге 1 даёт 20000)
const MAX_CELLS := 60000
const EPS := 0.001
## На сколько ю поверхность воды ниже уровня (чтобы не мерцать вровень с верхом листа)
const SURFACE_DROP := 0.05


## Ячейки домена, целиком лежащие внутри прямоугольника domain (мировые ю)
static func grid_domain(domain: Rect2, step: float) -> Rect2i:
	var x0 := ceili(domain.position.x / step - EPS)
	var z0 := ceili(domain.position.y / step - EPS)
	var x1 := floori(domain.end.x / step + EPS)
	var z1 := floori(domain.end.y / step + EPS)
	return Rect2i(x0, z0, maxi(0, x1 - x0), maxi(0, z1 - z0))


static func cell_of(p: Vector2, step: float) -> Vector2i:
	return Vector2i(floori(p.x / step), floori(p.y / step))


static func cell_center(c: Vector2i, step: float) -> Vector2:
	return Vector2((float(c.x) + 0.5) * step, (float(c.y) + 0.5) * step)


## Занятость по листам: точка занята, если лист в ней сплошной в слое воды [level_y - T, level_y)
static func blocker_for(level_y: float) -> Callable:
	var T: float = Global.settings.layer_height
	var lo := level_y - T
	var cand: Array[Dictionary] = []
	if is_instance_valid(TGM):
		for e in TGM.get_layers():
			var l := e.get_comp(C_TerrainLayer) as C_TerrainLayer
			if l == null or l.top_y() <= lo + EPS or l.base_y() >= level_y - EPS:
				continue
			cand.append({"layer": l, "rect": C_Contour.bounds_of(l.world_polygon())})
	return func(p: Vector2) -> bool:
		for c in cand:
			if not (c["rect"] as Rect2).has_point(p):
				continue
			for iv: Vector2 in (c["layer"] as C_TerrainLayer).solid_intervals_at(p):
				if iv.x < level_y - EPS and iv.y > lo + EPS:
					return true
		return false


## XX claude-table T2. Ячейка (центр в мире, ю) лежит на плите подмакетника. Секции есть: по их контурам (стол из нескольких секций,
## вода у вырезанного угла не вытекает); секций нет (стенд, тест): Callable() и домен-прямоугольник, как раньше
static func footprint_inside() -> Callable:
	if not is_instance_valid(LYM) or LYM.get_sections().is_empty():
		return Callable()
	return func(p: Vector2) -> bool: return LYM.contains(p.x, p.y)


## Залить. Результат:
##  ok - область найдена, иначе why = причина ("" при ok);
##  cells - Dictionary Vector2i -> true; count; touches_edge - область дошла до края домена;
##  bounds - Rect2 области в мире (ю); dom - Rect2i ячеек домена.
## inside (необязательно): Callable(Vector2) -> bool, центр ячейки на плите. Ячейка вне плиты это край домена (стена, не утечка)
static func fill(seed_pos: Vector2, level_y: float, domain: Rect2, step: float, blocked: Callable, max_cells: int = MAX_CELLS,
		inside: Callable = Callable()) -> Dictionary:
	var res := {"ok": false, "why": "", "cells": {}, "count": 0, "touches_edge": false, "bounds": Rect2(), "dom": Rect2i()}
	var T: float = Global.settings.layer_height
	if level_y < T - EPS:
		res["why"] = "Уровень воды ниже первого слоя"
		return res
	var dom := grid_domain(domain, step)
	res["dom"] = dom
	var s := cell_of(seed_pos, step)
	if not dom.has_point(s) or (inside.is_valid() and not inside.call(cell_center(s, step))):
		res["why"] = "Точка за краем стола"
		return res
	if blocked.call(cell_center(s, step)):
		res["why"] = "Здесь выше уровня воды"
		return res
	var cells := {}
	cells[s] = true
	var queue: Array[Vector2i] = [s]
	var head := 0
	var edge := false
	var lo := s
	var hi := s
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if cells.has(n):
				continue
			if not dom.has_point(n) or (inside.is_valid() and not inside.call(cell_center(n, step))):
				edge = true
				continue
			if blocked.call(cell_center(n, step)):
				continue
			cells[n] = true
			queue.append(n)
			lo = Vector2i(mini(lo.x, n.x), mini(lo.y, n.y))
			hi = Vector2i(maxi(hi.x, n.x), maxi(hi.y, n.y))
		if queue.size() > max_cells:
			res["why"] = "Слишком большая область"
			return res
	res["ok"] = true
	res["cells"] = cells
	res["count"] = cells.size()
	res["touches_edge"] = edge
	res["bounds"] = Rect2(Vector2(lo) * step, Vector2(hi - lo + Vector2i.ONE) * step)
	return res


## Горизонтальные полосы области: Vector3i(z, x0, x1) на строку, x1 не входит. Для меша и подсчёта
static func runs(cells: Dictionary) -> Array[Vector3i]:
	var rows := {}
	for c: Vector2i in cells:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	var zs := rows.keys()
	zs.sort()
	var res: Array[Vector3i] = []
	for z: int in zs:
		var xs: Array = rows[z]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size()):
			var x: int = xs[i]
			if x != prev + 1:
				res.append(Vector3i(z, start, prev + 1))
				start = x
			prev = x
		res.append(Vector3i(z, start, prev + 1))
	return res


## Стенки у края домена: мокрые ячейки на границе дают вертикальную грань. Элемент: {"a": Vector2, "b": Vector2}
## (концы грани в мире, ю), обход так, что нормаль смотрит наружу
static func edge_walls(cells: Dictionary, dom: Rect2i, step: float, inside: Callable = Callable()) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	if inside.is_valid():
		# XX claude-table T2: край это любая грань мокрой ячейки, за которой нет плиты (или домена)
		for c: Vector2i in cells:
			var x0 := float(c.x) * step
			var z0 := float(c.y) * step
			if _outside(c + Vector2i(-1, 0), dom, step, inside):
				res.append({"a": Vector2(x0, z0 + step), "b": Vector2(x0, z0)})
			if _outside(c + Vector2i(1, 0), dom, step, inside):
				res.append({"a": Vector2(x0 + step, z0), "b": Vector2(x0 + step, z0 + step)})
			if _outside(c + Vector2i(0, -1), dom, step, inside):
				res.append({"a": Vector2(x0, z0), "b": Vector2(x0 + step, z0)})
			if _outside(c + Vector2i(0, 1), dom, step, inside):
				res.append({"a": Vector2(x0 + step, z0 + step), "b": Vector2(x0, z0 + step)})
		return res
	var x_min := float(dom.position.x) * step
	var x_max := float(dom.end.x) * step
	var z_min := float(dom.position.y) * step
	var z_max := float(dom.end.y) * step
	for c: Vector2i in cells:
		var x0 := float(c.x) * step
		var z0 := float(c.y) * step
		if c.x == dom.position.x:   # запад: нормаль -X
			res.append({"a": Vector2(x_min, z0 + step), "b": Vector2(x_min, z0)})
		if c.x == dom.end.x - 1:   # восток: нормаль +X
			res.append({"a": Vector2(x_max, z0), "b": Vector2(x_max, z0 + step)})
		if c.y == dom.position.y:   # север (-Z): нормаль -Z
			res.append({"a": Vector2(x0, z_min), "b": Vector2(x0 + step, z_min)})
		if c.y == dom.end.y - 1:   # юг (+Z): нормаль +Z
			res.append({"a": Vector2(x0 + step, z_max), "b": Vector2(x0, z_max)})
	return res


static func _outside(c: Vector2i, dom: Rect2i, step: float, inside: Callable) -> bool:
	return not dom.has_point(c) or not inside.call(cell_center(c, step))
