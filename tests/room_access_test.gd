extends Node

## ATTN_25 RM1+RM2: кто может менять активную комнату и что убрано из Observe.
## Запуск: открыть tests/room_access_test.tscn и нажать F6. Результат в Output: во всех строках OK, в конце ИТОГ: OK.
## Предупреждения «RoomBuilder.request_room: ...» в Output ожидаемы: это отказы, которые тест вызывает специально.
## Проверяет: права по источникам (start, scenario, load всегда; admin только при Global.debug_mode; остальные нет),
## неизвестный id не ломает текущую комнату, загрузка с неизвестным id даёт комнату по умолчанию,
## в Observe нет категории Room и карточек выбора комнаты.

var _bad := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_bad += 1
	print("  %s %s %s" % ["OK " if cond else "ОШИБКА", label, detail])


func _ready() -> void:
	print("== 1. Права источников (RoomBuilder.can_change)")
	check("start может", RoomBuilder.can_change(&"start"))
	check("scenario может", RoomBuilder.can_change(&"scenario"))
	check("load может", RoomBuilder.can_change(&"load"))
	for src in [&"observe", &"build", &"operate", &"player", &"library", &""]:
		check("источник '%s' не может" % src, not RoomBuilder.can_change(src))
	var dbg := Global.debug_mode
	Global.debug_mode = true
	check("admin может при debug_mode", RoomBuilder.can_change(&"admin"))
	Global.debug_mode = false
	check("admin не может без debug_mode", not RoomBuilder.can_change(&"admin"))
	Global.debug_mode = dbg

	print("== 2. Observe без комнаты")
	var cats: Array[StringName] = []
	for c in CardCatalogProvider.CATEGORIES:
		cats.append(c.id)
	check("в списке пять категорий", cats == [&"look", &"light", &"camera", &"photo", &"weather"], str(cats))
	check("карточек категории room нет", not CardCatalogProvider.CARDS.has(&"room"))
	var provider := CardCatalogProvider.new()
	var picks := 0
	for cat in cats:
		for d: Dictionary in provider._cards_for(cat):
			if d.get("group", &"") == &"room_pick" or String(d.id).begins_with("room_") or String(d.id).begins_with("wall_"):
				picks += 1
	check("карточек выбора комнаты и цвета стен нет", picks == 0, "найдено %d" % picks)
	check("Global.start_room это StringName", typeof(Global.start_room) == TYPE_STRING_NAME)

	print("== 3. request_room")
	if Global.fast_debug:
		print("  пропуск: Global.fast_debug = true, комнату не строим")
		print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)
		return
	var rb := RoomBuilder.new()
	add_child(rb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("комната построена", rb.is_in_group(&"room_root"))
	var first := rb.get_room_id()
	check("стартовая комната по умолчанию", first == RoomCatalog.DEFAULT_ID, str(first))

	check("observe не меняет комнату", not rb.request_room(&"attic", &"observe") and rb.get_room_id() == first)
	check("пустой источник не меняет комнату", not rb.request_room(&"attic", &"") and rb.get_room_id() == first)
	check("start меняет комнату", rb.request_room(&"attic", &"start") and rb.get_room_id() == &"attic", str(rb.get_room_id()))
	check("та же комната: true", rb.request_room(&"attic", &"scenario") and rb.get_room_id() == &"attic")
	check("неизвестный id (scenario) отклонён", not rb.request_room(&"no_such_room", &"scenario") and rb.get_room_id() == &"attic")
	check("неизвестный id (start) отклонён", not rb.request_room(&"no_such_room", &"start") and rb.get_room_id() == &"attic")
	check("комната цела после отказов", rb.is_in_group(&"room_root") and rb.table != null and is_instance_valid(rb.table))

	Global.debug_mode = false
	check("admin без debug_mode не меняет", not rb.request_room(&"cube", &"admin") and rb.get_room_id() == &"attic")
	Global.debug_mode = true
	check("admin при debug_mode меняет", rb.request_room(&"cube", &"admin") and rb.get_room_id() == &"cube", str(rb.get_room_id()))
	Global.debug_mode = dbg

	check("load с неизвестным id даёт комнату по умолчанию", rb.request_room(&"no_such_room", &"load")
			and rb.get_room_id() == RoomCatalog.DEFAULT_ID, str(rb.get_room_id()))
	check("load возвращает комнату сейва", rb.request_room(&"attic", &"load") and rb.get_room_id() == &"attic")

	print("== 4. Видимость комнаты и потолка (F3 → Toggles)")
	check("комната видна по умолчанию", rb.is_room_visible())
	rb.set_room_visible(false)
	check("set_room_visible(false)", not rb.is_room_visible() and not rb.visuals.visible)
	rb.set_room_visible(true)
	check("потолок скрыт по умолчанию", not rb.is_ceiling_visible())
	rb.set_ceiling_visible(true)
	check("set_ceiling_visible(true)", rb.is_ceiling_visible())
	rb.set_ceiling_visible(false)

	rb.queue_free()
	await get_tree().process_frame
	print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)
