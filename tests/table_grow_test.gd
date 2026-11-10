extends Node

# XX claude-table T2 (новый файл)
## ATTN_23 T2+T3: наращивание секциями, опоры, высота стола, вода по футпринту. Запуск: открыть tests/table_grow_test.tscn и F6.
## Результат в Output: во всех строках OK, в конце ИТОГ: OK.
## Проверяет: снап и общее ребро TableTool; ножки TableSupports (стол v1 и стол из двух секций); LYM.footprint, правило удаления
## секции с объектами; домен воды по Г-образному столу; высота стола: пол, ножки и границы камеры в RoomBuilder.

var _bad := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_bad += 1
	print("  %s %s %s" % ["OK " if cond else "ОШИБКА", label, detail])


func _section(preset: String, pos: Vector2, size: Vector2 = Vector2.ZERO) -> Entity:
	var f := EntityFactory.new()
	var e := f.create_from_setting(load("res://data/table/objects/%s.tres" % preset) as EntitySetting)
	f.free()
	if size != Vector2.ZERO:
		(e.get_comp(C_Contour) as C_Contour).set_rect(size)
	e.position = Vector3(pos.x, 0.0, pos.y)
	add_child(e)
	return e


func _ready() -> void:
	print("== 1. TableTool: снап и общее ребро")
	var table: Array[Rect2] = [Rect2(-100, -50, 200, 100)]
	var c := TableTool.snap_center(Vector2(155, 0), Vector2(100, 100), table)
	check("справа прилипает ребром к ребру", c == Vector2(150, 0), str(c))
	c = TableTool.snap_center(Vector2(0, 98), Vector2(100, 100), table)
	check("снизу прилипает, по X ровно как курсор", c.y == 100.0 and c.x == 0.0, str(c))
	c = TableTool.snap_center(Vector2(400, 0), Vector2(100, 100), table)
	check("далеко: без прилипания, на сетке", c == Vector2(400, 0), str(c))
	c = TableTool.snap_center(Vector2(300.4, 20.4), Vector2(100, 50), table)
	check("далеко: левый верхний угол на сетке 1 u", c == Vector2(300.0, 20.0), str(c))
	check("общее ребро", TableTool.shares_edge(Rect2(-100, -50, 200, 100), Rect2(100, -50, 100, 100)))
	check("ребро сверху", TableTool.shares_edge(Rect2(-100, -50, 200, 100), Rect2(-50, 50, 100, 50)))
	check("касание углом не стык", not TableTool.shares_edge(Rect2(-100, -50, 200, 100), Rect2(100, 50, 100, 100)))
	check("зазор не стык", not TableTool.shares_edge(Rect2(-100, -50, 200, 100), Rect2(105, -50, 100, 100)))
	check("пересечение не ребро", not TableTool.shares_edge(Rect2(-100, -50, 200, 100), Rect2(0, 0, 100, 100)))

	print("== 2. Ножки: стол v1 и стол из двух секций")
	var leg := RoomConfig.new().table_leg
	var v1: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-100, -50), Vector2(100, -50), Vector2(100, 50), Vector2(-100, 50)])]
	var legs := TableSupports.leg_positions(v1, leg)
	var ex := 100.0 - leg * 0.5 - TableSupports.EDGE_INSET
	var ez := 50.0 - leg * 0.5 - TableSupports.EDGE_INSET
	var ok := legs.size() == 4
	for p in [Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(ex, ez), Vector2(-ex, ez)]:
		ok = ok and legs.has(p)
	check("стол v1: 4 ножки как раньше", ok, str(legs))

	LYM.reset()
	var a := _section("sec_200x100", Vector2.ZERO)
	var b := _section("sec_100x100", Vector2(150, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("секций две", LYM.get_sections().size() == 2)
	var fp := LYM.footprint()
	check("футпринт: касающиеся секции слиты в один контур", fp.size() == 1, str(fp.size()))
	legs = TableSupports.leg_positions(fp, leg)
	check("стол 300 x 100: 4 угла и по одной ножке на длинных рёбрах", legs.size() == 6, str(legs))
	check("table_rect 300 x 100", LYM.table_rect() == Rect2(-100, -50, 300, 100))
	check("плита толщиной 5", is_equal_approx(LYM.plate_thickness(), 5.0), str(LYM.plate_thickness()))
	var space := get_viewport().world_3d.direct_space_state
	var seam_ok := true
	for z in [-49.0, -10.0, 0.0, 10.0, 49.0]:
		for x in [99.99, 100.0, 100.01]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 50.0, z), Vector3(x, -200.0, z), Global.active_layers(['ground']))
			var hit := space.intersect_ray(q)
			seam_ok = seam_ok and not hit.is_empty() and absf(hit.position.y) < 0.001
	check("на стыке секций луч попадает в ground (щели нет)", seam_ok)

	print("== 3. Убрать секцию")
	check("пустая секция убирается", LYM.removal_block_reason(b) == "")
	var thing := Entity.new()
	thing.position = Vector3(150, 0, 10)
	add_child(thing)
	check("объект на секции: убрать нельзя", LYM.removal_block_reason(b) != "", LYM.removal_block_reason(b))
	check("объект на секции: убрать нельзя (список)", LYM.objects_on_section(b).has(thing))
	check("объект на другой секции не мешает", LYM.removal_block_reason(a) == "" and not LYM.objects_on_section(a).has(thing))
	var notes := [""]
	LYM.notice.connect(func(t: String): notes[0] = t)
	b.kill_me()
	check("kill_me отказал и сказал почему", is_instance_valid(b) and not b.is_queued_for_deletion() and notes[0] != "", notes[0])
	thing.free()
	check("без объекта убирается", LYM.removal_block_reason(b) == "")
	b.free()
	a.free()

	print("== 4. Вода: Г-образный стол")
	var s1 := _section("sec_200x100", Vector2.ZERO)
	var s2 := _section("sec_100x100", Vector2(150, -25), Vector2(100, 50))
	await get_tree().physics_frame
	var dom := TGM.table_rect()
	check("домен 300 x 100", dom == Rect2(-100, -50, 300, 100), str(dom))
	var empty := func(_p: Vector2) -> bool: return false
	var ly := float(Global.settings.layer_height) * 2.0
	var inside := WaterFill.footprint_inside()
	check("footprint_inside есть при секциях", inside.is_valid())
	var res := WaterFill.fill(Vector2(0.5, 0.5), ly, dom, 5.0, empty, WaterFill.MAX_CELLS, inside)
	check("вода заливает плиту: 800 + 200 ячеек", res["ok"] and res["count"] == 1000, str(res["count"]))
	check("вода дошла до края", res["touches_edge"])
	var corner := WaterFill.fill(Vector2(150.5, 25.5), ly, dom, 5.0, empty, WaterFill.MAX_CELLS, inside)
	check("вырезанный угол не залить", not corner["ok"], str(corner["why"]))
	var walls := WaterFill.edge_walls(res["cells"], res["dom"], 5.0, inside)
	check("стенки по контуру Г-образного стола: 2 * (60 + 20) = 160 граней", walls.size() == 160, str(walls.size()))
	s1.free()
	s2.free()

	print("== 5. Высота стола")
	LYM.reset()
	var fired := [0]
	var h := func(): fired[0] += 1
	LYM.layout_changed.connect(h)
	LYM.set_height(90.0)
	check("высота 90, сигнал", LYM.config.height == 90.0 and fired[0] == 1)
	LYM.set_height(90.0)
	check("та же высота: без сигнала", fired[0] == 1)
	LYM.set_height(500.0)
	check("не выше предела", LYM.config.height == LayoutConfig.HEIGHT_MAX)
	LYM.set_height(1.0)
	check("не ниже предела", LYM.config.height == LayoutConfig.HEIGHT_MIN)
	LYM.set_height(50.0)
	var note := [""]
	LYM.notice.connect(func(t: String): note[0] = t)
	LYM.step_height(2)
	check("шаг высоты +2 это +10 u", LYM.config.height == 60.0 and note[0] != "", note[0])
	LYM.layout_changed.disconnect(h)
	LYM.reset()

	if Global.fast_debug:
		print("  пропуск: Global.fast_debug = true, комнату не строим")
		print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)
		return

	print("== 6. Комната: пол, ножки, границы камеры")
	var rb := RoomBuilder.new()
	add_child(rb)
	var sec := LYM.ensure_start_section(self)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var legs0 := rb.table.get_child_count()
	var top0 := rb.get_bounds().end.y
	check("стол v1: 4 ножки", legs0 == 4, str(legs0))
	check("пол на месте (смещения нет)", is_equal_approx(rb.floor_offset(), 0.0) and (rb.visuals == null or is_zero_approx(rb.visuals.position.y)))
	LYM.set_height(90.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("высота 90: пол ниже на 40", is_equal_approx(rb.floor_offset(), -40.0), str(rb.floor_offset()))
	if rb.visuals != null:
		check("комната сдвинута вместе с полом", is_equal_approx(rb.visuals.position.y, -40.0), str(rb.visuals.position.y))
	check("ножки пересобраны, их 4", rb.table.get_child_count() == 4)
	var leg_node := rb.table.get_child(0) as Node3D
	check("ножка длиннее: низ на полу", leg_node != null and is_equal_approx(leg_node.position.y - _leg_half_height(leg_node), -90.0), str(leg_node.position.y if leg_node else 0.0))
	check("потолок комнаты ниже вместе с полом", is_equal_approx(rb.get_bounds().end.y, top0 - 40.0), "%s -> %s" % [top0, rb.get_bounds().end.y])
	LYM.set_height(50.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("высота 50: всё вернулось", is_equal_approx(rb.floor_offset(), 0.0) and rb.table.get_child_count() == 4)
	var limits := LYM.placement_limits()
	check("зона постановки: проход от стен, центр внутри", limits.size.x > 0.0 and limits.has_point(Vector2.ZERO), str(limits))
	rb.queue_free()
	if sec != null:
		sec.free()
	LYM.reset()

	print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)


func _leg_half_height(n: Node3D) -> float:
	var m := n.get_node_or_null("Mesh") as MeshInstance3D
	if m == null:
		for ch in n.get_children():
			if ch is MeshInstance3D:
				m = ch
	return (m.mesh as BoxMesh).size.y * 0.5 if m != null and m.mesh is BoxMesh else 0.0
