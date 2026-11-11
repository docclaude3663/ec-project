class_name TableRules extends RefCounted

# XX claude-table T4 (новый файл)
###################################
## Правила размещения секций относительно комнаты и опор (ATTN_23 §23.4, T4 и T5). Чистые функции, без узлов и без LYM.
###################################
## Стены берутся из RoomConfig: внутренний размер size (центр в нуле), окно в северной стене (-Z), дверь в южной (+Z).
## Комната shape = none (стенд): стен нет. Мансарда: восточная стена это скос крыши, кронштейны на неё не крепятся.
## Секции прямоугольные: правила считают по их ограничивающим прямоугольникам (Rect2: x = X, y = Z).

const EPS := 0.01
## Мягкое правило глубины для кронштейнов: дальше от стены только предупреждение «нужны опоры», u
const WALL_DEPTH_SOFT := 60.0

const NORTH := &"north"
const SOUTH := &"south"
const WEST := &"west"
const EAST := &"east"


static func has_walls(cfg: RoomConfig) -> bool:
	return cfg != null and cfg.shape != &"none"


## Можно ли крепить кронштейны к этой стене (в мансарде восточная стена это скос)
static func mountable(cfg: RoomConfig, wall: StringName) -> bool:
	return has_walls(cfg) and not (cfg.shape == &"attic" and wall == EAST)


## Внутренний прямоугольник комнаты (центр в нуле)
static func interior(cfg: RoomConfig) -> Rect2:
	var s := Vector2(cfg.size.x, cfg.size.z)
	return Rect2(-s * 0.5, s)


## Зазор от секции до каждой стены, u (отрицательный: секция выходит за стену)
static func gaps(rect: Rect2, cfg: RoomConfig) -> Dictionary:
	var r := interior(cfg)
	return {
		NORTH: rect.position.y - r.position.y,
		SOUTH: r.end.y - rect.end.y,
		WEST: rect.position.x - r.position.x,
		EAST: r.end.x - rect.end.x,
	}


## Стены, к которым секция примыкает вплотную (и к которым можно крепить кронштейны)
static func wall_contacts(rect: Rect2, cfg: RoomConfig) -> Array[StringName]:
	var res: Array[StringName] = []
	if not has_walls(cfg):
		return res
	var g := gaps(rect, cfg)
	for w: StringName in [NORTH, SOUTH, WEST, EAST]:
		if absf(float(g[w])) <= EPS and mountable(cfg, w):
			res.append(w)
	return res


## Секция закрывает окно или дверь (её ребро у стены лежит напротив проёма). Пусто: не закрывает
static func opening_reason(rect: Rect2, cfg: RoomConfig) -> String:
	for w in wall_contacts(rect, cfg):
		var op: Dictionary = {}
		var what := ""
		if w == NORTH:
			op = cfg.window
			what = "окно"
		elif w == SOUTH:
			op = cfg.door
			what = "дверь"
		if op.is_empty():
			continue
		var l := float(op.get("x", 0.0)) - float(op.get("w", 0.0)) * 0.5
		var r := float(op.get("x", 0.0)) + float(op.get("w", 0.0)) * 0.5
		if minf(rect.end.x, r) - maxf(rect.position.x, l) > EPS:
			return "Секция закрывает %s" % what
	return ""


## Можно ли поставить секцию в этом месте с точки зрения комнаты; пусто: можно.
## Ножки и рама: от стен не ближе aisle. Кронштейны: можно вплотную к стене (кроме скоса), остальные стороны не ближе aisle
static func placement_reason(rect: Rect2, cfg: RoomConfig, support: int, aisle: float) -> String:
	if not has_walls(cfg):
		return ""
	var g := gaps(rect, cfg)
	var wall_mode := support == LayoutConfig.Support.WALL
	for w: StringName in [NORTH, SOUTH, WEST, EAST]:
		var gap := float(g[w])
		if gap < -EPS:
			return "Выходит за пределы комнаты"
		if wall_mode and gap <= EPS and mountable(cfg, w):
			continue
		if gap < aisle - EPS:
			if wall_mode and gap <= EPS:
				return "Скос крыши: сюда кронштейны не крепятся"
			return "Выходит за пределы комнаты (проход %d u)" % int(aisle)
	if wall_mode:
		return opening_reason(rect, cfg)
	return ""


## Компоненты связности секций по общим рёбрам: списки индексов в rects
static func components(rects: Array[Rect2]) -> Array[PackedInt32Array]:
	var parent: Array[int] = []
	for i in rects.size():
		parent.append(i)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if TableTool.shares_edge(rects[i], rects[j]):
				var a := _root(parent, i)
				var b := _root(parent, j)
				if a != b:
					parent[b] = a
	var groups := {}
	for i in rects.size():
		var r := _root(parent, i)
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		(groups[r] as PackedInt32Array).append(i)
	var res: Array[PackedInt32Array] = []
	for k in groups:
		res.append(groups[k])
	return res


static func _root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


## Подходит ли такая раскладка секций режиму кронштейнов; пусто: подходит.
## Каждая связная группа должна крепиться к стене хотя бы одной секцией, окно и дверь не закрыты
static func wall_layout_reason(rects: Array[Rect2], cfg: RoomConfig) -> String:
	if rects.is_empty():
		return ""
	if not has_walls(cfg):
		return "В этой комнате нет стен"
	for r in rects:
		var why := opening_reason(r, cfg)
		if why != "":
			return why
	for comp in components(rects):
		var attached := false
		for i in comp:
			if not wall_contacts(rects[i], cfg).is_empty():
				attached = true
				break
		if not attached:
			return "Часть стола не касается стены"
	return ""


## Мягкое правило глубины: группа секций глубже WALL_DEPTH_SOFT от стены (от лучшей из стен, к которым она крепится).
## Пусто: всё в пределах. Не запрет, а предупреждение
static func wall_depth_warning(rects: Array[Rect2], cfg: RoomConfig) -> String:
	if not has_walls(cfg):
		return ""
	var worst := 0.0
	for comp in components(rects):
		var touched: Array[StringName] = []
		for i in comp:
			for w in wall_contacts(rects[i], cfg):
				if not touched.has(w):
					touched.append(w)
		if touched.is_empty():
			continue
		var best := INF
		for w in touched:
			var depth := 0.0
			for i in comp:
				depth = maxf(depth, _depth_from(rects[i], cfg, w))
			best = minf(best, depth)
		worst = maxf(worst, best)
	if worst > WALL_DEPTH_SOFT + EPS:
		return "Глубина %d u от стены: кронштейны не держат, нужны опоры" % int(round(worst))
	return ""


## Насколько секция уходит в комнату от стены wall, u
static func _depth_from(rect: Rect2, cfg: RoomConfig, wall: StringName) -> float:
	var r := interior(cfg)
	match wall:
		NORTH:
			return rect.end.y - r.position.y
		SOUTH:
			return r.end.y - rect.position.y
		WEST:
			return rect.end.x - r.position.x
		_:
			return r.end.x - rect.position.x
