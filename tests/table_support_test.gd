extends Node

# XX claude-table T4 (новый файл)
## ATTN_23 T4+T5: рама на полу и кронштейны к стене. Запуск: открыть tests/table_support_test.tscn и F6.
## Результат в Output: во всех строках OK, в конце ИТОГ: OK.
## Проверяет: правила комнаты TableRules (проход, стена, окно, дверь, скос мансарды, стенд без стен), связность и глубину;
## план опор TableSupports.parts (ножки, рама, кронштейны); LYM.set_support и высоту рамы; RoomBuilder строит опоры по виду.

var _bad := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_bad += 1
	print("  %s %s %s" % ["OK " if cond else "ОШИБКА", label, detail])


func _section(pos: Vector2, size: Vector2) -> Entity:
	var f := EntityFactory.new()
	var e := f.create_from_setting(load("res://data/table/objects/sec_100x100.tres") as EntitySetting)
	f.free()
	(e.get_comp(C_Contour) as C_Contour).set_rect(size)
	e.position = Vector3(pos.x, 0.0, pos.y)
	add_child(e)
	return e


func _poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _count(parts: Array[Dictionary], nm: String) -> int:
	var n := 0
	for p in parts:
		if String(p["name"]) == nm:
			n += 1
	return n


func _ready() -> void:
	var cfg := RoomConfig.new()   # 480 x 380, окно на севере (x 0, w 170), дверь на юге (x 100, w 80)
	var legs := LayoutConfig.Support.LEGS
	var wall := LayoutConfig.Support.WALL
	var plinth := LayoutConfig.Support.PLINTH
	print("== 1. Правила комнаты")
	check("ножки: у стены нельзя (проход)", TableRules.placement_reason(Rect2(-240, -50, 100, 100), cfg, legs, 60.0) != "")
	check("ножки: с проходом можно", TableRules.placement_reason(Rect2(-100, -50, 200, 100), cfg, legs, 60.0) == "")
	check("за стену нельзя в любом режиме", TableRules.placement_reason(Rect2(-250, -50, 100, 100), cfg, wall, 60.0) != "")
	check("кронштейны: вплотную к западной стене можно", TableRules.placement_reason(Rect2(-240, -50, 100, 100), cfg, wall, 60.0) == "")
	check("кронштейны: зазор 30 до стены нельзя", TableRules.placement_reason(Rect2(-210, -50, 100, 100), cfg, wall, 60.0) != "")
	check("кронштейны: напротив окна красный", TableRules.placement_reason(Rect2(-100, -190, 200, 100), cfg, wall, 60.0) == "Секция закрывает окно")
	check("кронштейны: рядом с окном можно", TableRules.placement_reason(Rect2(100, -190, 100, 100), cfg, wall, 60.0) == "")
	check("кронштейны: напротив двери красный", TableRules.placement_reason(Rect2(60, 90, 80, 100), cfg, wall, 60.0) == "Секция закрывает дверь")
	check("контакты секции у угла: две стены", TableRules.wall_contacts(Rect2(-240, -190, 100, 100), cfg).size() == 2)
	var attic := RoomConfig.new()
	attic.shape = &"attic"
	check("мансарда: на восточную стену не крепим", TableRules.wall_contacts(Rect2(140, -50, 100, 100), attic).is_empty())
	check("мансарда: у скоса красный", TableRules.placement_reason(Rect2(140, -50, 100, 100), attic, wall, 60.0) != "")
	var none := RoomConfig.new()
	none.shape = &"none"
	check("стенд без стен: ограничений нет", TableRules.placement_reason(Rect2(-1000, -50, 100, 100), none, wall, 60.0) == "")
	var stand: Array[Rect2] = [Rect2(-100, -50, 200, 100)]
	check("стенд без стен: кронштейны нельзя", TableRules.wall_layout_reason(stand, none) != "")

	print("== 2. Связность и глубина")
	var v1: Array[Rect2] = [Rect2(-100, -50, 200, 100)]
	check("стол v1 посреди комнаты: к стене не крепится", TableRules.wall_layout_reason(v1, cfg) == "Часть стола не касается стены")
	var joined: Array[Rect2] = [Rect2(-100, -50, 200, 100), Rect2(-240, -50, 140, 100)]
	check("две секции стыком, одна у стены: крепится", TableRules.wall_layout_reason(joined, cfg) == "")
	check("одна группа", TableRules.components(joined).size() == 1)
	var apart: Array[Rect2] = [Rect2(-240, -50, 100, 100), Rect2(0, -50, 100, 100)]
	check("две отдельные: две группы", TableRules.components(apart).size() == 2)
	check("отдельная секция без стены: отказ", TableRules.wall_layout_reason(apart, cfg) != "")
	var shallow: Array[Rect2] = [Rect2(-240, -50, 60, 100)]
	var deep: Array[Rect2] = [Rect2(-240, -50, 100, 100)]
	check("глубина 60: без предупреждения", TableRules.wall_depth_warning(shallow, cfg) == "")
	check("глубина 100: предупреждение", TableRules.wall_depth_warning(deep, cfg).contains("100"), TableRules.wall_depth_warning(deep, cfg))

	print("== 3. План опор")
	var th := 5.0
	var fp_v1: Array[PackedVector2Array] = [_poly(Rect2(-100, -50, 200, 100))]
	var p_legs := TableSupports.parts(legs, fp_v1, 50.0, th, 6.0, cfg)
	check("ножки: 4 штуки как раньше", _count(p_legs, "Leg") == 4 and p_legs.size() == 4)
	var p_plinth := TableSupports.parts(plinth, fp_v1, 10.0, th, 6.0, cfg)
	check("рама: 4 бруса вдоль рёбер", _count(p_plinth, "Rail") == 4 and p_plinth.size() == 4, str(p_plinth.size()))
	var rail_ok := true
	for p in p_plinth:
		rail_ok = rail_ok and is_equal_approx((p["size"] as Vector3).y, 5.0) and is_equal_approx((p["center"] as Vector3).y, -7.5)
	check("рама: от пола (-10) до низа плиты (-5)", rail_ok)
	check("рама высотой 5 u: бруса нет (плита на полу)", TableSupports.parts(plinth, fp_v1, 5.0, th, 6.0, cfg).is_empty())
	var fp_wall: Array[PackedVector2Array] = [_poly(Rect2(-240, -50, 140, 100))]
	var p_wall := TableSupports.parts(wall, fp_wall, 50.0, th, 6.0, cfg)
	check("кронштейны: 3 штуки по 3 детали на западном ребре 100 u", p_wall.size() == 9 and _count(p_wall, "BracketArm") == 3, str(p_wall.size()))
	var det_ok := true
	var arm_ok := true
	for p in p_wall:
		det_ok = det_ok and (p["basis"] as Basis).determinant() > 0.99
		if String(p["name"]) == "BracketArm":
			arm_ok = arm_ok and is_equal_approx((p["size"] as Vector3).z, 40.0)
	check("повороты деталей без отражения", det_ok)
	check("полка вылетает на 40 u (предел)", arm_ok)
	var no_wall := TableSupports.parts(wall, fp_v1, 50.0, th, 6.0, cfg)
	check("кронштейны без стены: контур на ножках", _count(no_wall, "Leg") == 4 and _count(no_wall, "BracketArm") == 0)

	print("== 4. LYM: опоры и высота")
	LYM.reset()
	var a := _section(Vector2.ZERO, Vector2(200, 100))
	await get_tree().physics_frame
	check("опоры по умолчанию: ножки", LYM.config.support == legs and LYM.config.height == 50.0)
	check("кронштейны без комнаты: отказ", LYM.set_support(wall) != "" and LYM.config.support == legs)
	check("рама: высота подогнана до 10", LYM.set_support(plinth) == "" and LYM.config.support == plinth and LYM.config.height == 10.0, str(LYM.config.height))
	LYM.set_height(100.0)
	check("у рамы высота не больше 20", LYM.config.height == 20.0)
	LYM.set_height(10.0)
	check("с ножек на раму и обратно: высота 50 вернулась", LYM.set_support(legs) == "" and LYM.config.height == 50.0, str(LYM.config.height))
	LYM.set_height(90.0)
	LYM.set_support(plinth)
	LYM.set_height(15.0)
	LYM.set_support(legs)
	check("высоту меняли на раме: остаётся своя", LYM.config.height == 15.0, str(LYM.config.height))
	var st := LYM.get_state()
	LYM.set_support(plinth)
	LYM.set_state(st)
	check("загрузка состояния возвращает опоры и высоту", LYM.config.support == legs and LYM.config.height == 15.0)
	LYM.set_state({"support": plinth, "height": 90.0})
	check("сейв с рамой и высотой 90: высота в пределе рамы", LYM.config.support == plinth and LYM.config.height == 20.0)
	LYM.reset()
	a.free()

	if Global.fast_debug:
		print("  пропуск: Global.fast_debug = true, комнату не строим")
		print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)
		return

	print("== 5. Комната: кронштейны и рама в RoomBuilder")
	var rb := RoomBuilder.new()
	add_child(rb)
	var s1 := LYM.ensure_start_section(self)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("кронштейны: стол посреди комнаты, отказ", LYM.set_support(wall) == "Часть стола не касается стены")
	var s2 := _section(Vector2(-170, 0), Vector2(140, 100))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("кронштейны принимаются", LYM.set_support(wall) == "" and LYM.config.support == wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var brackets := 0
	var legs_n := 0
	for ch in rb.table.get_children():
		if ch.name.begins_with("BracketArm"):
			brackets += 1
		elif ch.name.begins_with("Leg"):
			legs_n += 1
	check("RoomBuilder построил кронштейны, ножек нет", brackets == 3 and legs_n == 0, "%d / %d" % [brackets, legs_n])
	check("убрать секцию, без которой стол отрывается от стены", LYM.removal_block_reason(s2).contains("крепление"), LYM.removal_block_reason(s2))
	check("новая секция у окна красная", LYM.placement_reason(Rect2(-100, -190, 200, 100)) == "Секция закрывает окно", LYM.placement_reason(Rect2(-100, -190, 200, 100)))
	check("новая секция в воздухе красная", LYM.placement_reason(Rect2(150, 0, 100, 100)) != "")
	check("предупреждение о глубине у стола 340 u", LYM.depth_warning() != "", LYM.depth_warning())
	check("рама: переключение разрешено, но высота 10", LYM.set_support(plinth) == "" and LYM.config.height == 10.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rails := 0
	for ch in rb.table.get_children():
		if ch.name.begins_with("Rail"):
			rails += 1
	check("RoomBuilder построил раму: рёбра футпринта", rails == 4 or rails == 6, str(rails))
	check("комната сдвинута по высоте рамы 10", is_equal_approx(rb.floor_offset(), -10.0 - rb.config.floor_y), str(rb.floor_offset()))
	check("ножки в комнате вернулись", LYM.set_support(legs) == "" and LYM.config.height == 50.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var legs_back := 0
	for ch in rb.table.get_children():
		if ch.name.begins_with("Leg"):
			legs_back += 1
	check("ножек у стола 340 x 100: 4 угла и по одной на длинных рёбрах", legs_back == 6, str(legs_back))
	rb.queue_free()
	s1.free()
	s2.free()
	LYM.reset()
	print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)
