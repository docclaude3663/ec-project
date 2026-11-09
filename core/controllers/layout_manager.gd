extends Node
# class_name не задаём: это синглтон LYM (autoload), как TGM и PGM
###########################
## 💡 LYM - Системный сервис (autoload). Подмакетник: паспорт (LayoutConfig) и запросы по плите стола.
############################
# XX claude-table T0 (новый файл)
##
## ATTN_23. Плиту стола строят секции-Entity (C_TableSection, T1): ставятся в EntitiesRoot, сохраняются как обычные
## объекты. LYM их не хранит, а находит по группе GROUP (как TGM листы пенопласта), поэтому список всегда свежий.
## Потребители (TGM.table_rect, домен воды) спрашивают LYM и про секции не знают.
## Верх плиты всегда y = 0; ground, трак и опоры знают только про слой ground, не про секции.
## Нет ни одной секции (быстрая загрузка fast_debug или секции ещё не созданы): стол берётся из паспорта комнаты, как в v1.

## ⚡ Подмакетник изменился (секция, высота, опоры, загрузка сейва). Слушают опоры, границы камеры, домен воды
signal layout_changed

## Группа секций (C_TableSection добавляет в неё свою Entity при готовности)
const GROUP := &"table_section"
## Стартовая секция новой игры и миграции старых сейвов: 200 x 100 (стол v1)
const START_SECTION := "res://data/table/objects/sec_200x100.tres"

## Паспорт текущего макета. Заменяется целиком только через set_state / reset
var config := LayoutConfig.new()


## Настоящие секции стола: без призраков и удаляемых
func get_sections() -> Array[Entity]:
	var res: Array[Entity] = []
	if not is_inside_tree():
		return res
	for n in get_tree().get_nodes_in_group(GROUP):
		var e := n as Entity
		if e == null or not e.is_inside_tree() or e.is_queued_for_deletion() or e.has_comp(C_Ghost):
			continue
		res.append(e)
	return res


## Контур секции в мире (x = X, y = Z). Пусто, если у Entity нет плиты
func section_polygon(e: Entity) -> PackedVector2Array:
	var sec := e.get_comp(C_TableSection) as C_TableSection
	return sec.world_polygon() if sec else PackedVector2Array()


## Лежит ли точка (x, z) на плите хотя бы одной секции. Ребро считается плитой
func contains(x: float, z: float) -> bool:
	var pt := Vector2(x, z)
	for e in get_sections():
		var poly := section_polygon(e)
		if poly.size() >= 3 and (Geometry2D.is_point_in_polygon(pt, poly) or _on_edge(pt, poly)):
			return true
	return false


static func _on_edge(pt: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in n:
		if Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[(i + 1) % n]).distance_to(pt) < 0.001:
			return true
	return false


## Секцию можно убрать: последняя остаётся (ATTN_23 §23.2, инвариант 4). Секция, которой нет в списке, убирается свободно
func can_remove_section(e: Entity) -> bool:
	var list := get_sections()
	return not list.has(e) or list.size() > 1


## Ограничивающий прямоугольник плиты в мире (XZ): объединение секций. Нет секций: стартовая плита v1 из паспорта комнаты
func table_rect() -> Rect2:
	var r := Rect2()
	var any := false
	for e in get_sections():
		var poly := section_polygon(e)
		if poly.size() < 3:
			continue
		var b := C_Contour.bounds_of(poly)
		r = b if not any else r.merge(b)
		any = true
	if any:
		return r
	return _room_table_rect()


## Стол v1 из паспорта комнаты (RoomConfig.table_top), центр в (0, 0)
func _room_table_rect() -> Rect2:
	var size := RoomConfig.new().table_top
	if is_inside_tree():
		var rb := get_tree().get_first_node_in_group(&"room_root")
		if rb != null and rb.get("config") is RoomConfig:
			size = (rb.get("config") as RoomConfig).table_top
	return Rect2(-size * 0.5, size)


## Стартовая секция, если стол пуст: новая игра, сейв до подмакетника, очистка макета (ATTN_23 §23.2, инвариант 5).
## Размер и толщину берёт из паспорта комнаты (RoomConfig.table_top: стол v1 остаётся источником миграции).
## root: куда класть секцию (EntitiesRoot). Возвращает созданную секцию или null (секции уже есть, fast_debug)
func ensure_start_section(root: Node) -> Entity:
	if Global.fast_debug or root == null or not get_sections().is_empty():
		return null
	var setting := load(START_SECTION) as EntitySetting
	if setting == null:
		push_error("LYM: нет стартовой секции %s" % START_SECTION)
		return null
	var factory := EntityFactory.new()
	var e := factory.create_from_setting(setting)
	factory.free()
	var rb := get_tree().get_first_node_in_group(&"room_root")
	if rb != null and rb.get("config") is RoomConfig:
		var cfg := rb.get("config") as RoomConfig
		var contour := e.get_comp(C_Contour) as C_Contour
		if contour != null and contour.size() != cfg.table_top:
			contour.set_rect(cfg.table_top)
		var sec := e.get_comp(C_TableSection) as C_TableSection
		if sec != null:
			sec.thickness = cfg.table_top_thickness
	root.add_child(e)
	return e


## Состояние для SavedGame.layout
func get_state() -> Dictionary:
	return config.get_state()


## Загрузка сейва. Пустой словарь (сейв до подмакетника): значения по умолчанию, стол как в v1
func set_state(d: Dictionary) -> void:
	config = LayoutConfig.new()
	if not d.is_empty():
		config.set_state(d)
	layout_changed.emit()


## Новый макет: всё по умолчанию
func reset() -> void:
	set_state({})
