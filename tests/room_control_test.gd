extends Node

## ATTN_25 RM5: управляемые объекты комнаты (RoomControl, RoomControlRegistry, RoomControlDef, RoomMechanism).
## Запуск: открыть tests/room_control_test.tscn и нажать F6. Результат в Output: во всех строках OK, в конце ИТОГ: OK.
## Проверяет на собранной в коде сцене: переключатель и ползунок света, группа, механизмы SLIDE, ROTATE и ANIM (поза по состоянию 0..1),
## повтор id и узлы не того типа (замечания, без падения), метка без id, scope; а также метки в настоящей сцене attic.
## Предупреждения «[RoomControl] ...» и «[RoomMechanism] ...» в Output ожидаемы: это отказы, которые тест вызывает специально.

var _bad := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_bad += 1
	print("  %s %s %s" % ["OK " if cond else "ОШИБКА", label, detail])


func _ctl(parent: Node, id: StringName, kind: RoomControl.Kind = RoomControl.Kind.TOGGLE, scope: RoomControl.Scope = RoomControl.Scope.STUDIO,
		group: StringName = &"", mech: MechanismConfig = null, default_value := 1.0) -> RoomControl:
	var c := RoomControl.new()
	c.id = id
	c.kind = kind
	c.scope = scope
	c.group = group
	c.mechanism = mech
	c.default_value = default_value
	parent.add_child(c)
	return c


func _light(root: Node, name: String, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = name
	l.light_energy = energy
	root.add_child(l)
	return l


func _mech(actuator: MechanismConfig.Actuator, id: StringName, axis := Vector3.RIGHT, travel := 10.0) -> MechanismConfig:
	var m := MechanismConfig.new()
	m.id = id
	m.actuator = actuator
	m.axis = axis
	m.travel = travel
	m.duration = 1.0
	return m


func _ready() -> void:
	print("== 1. Свет: переключатель, ползунок, группа")
	var root := Node3D.new()
	add_child(root)
	var lamp := _light(root, "Lamp", 80.0)
	_ctl(lamp, &"lamp_a", RoomControl.Kind.TOGGLE, RoomControl.Scope.OBSERVE)
	var dim := _light(root, "Dim", 50.0)
	_ctl(dim, &"dim", RoomControl.Kind.SLIDER, RoomControl.Scope.STUDIO, &"", null, 0.5)
	var g1 := _light(root, "G1", 10.0)
	var g2 := _light(root, "G2", 20.0)
	_ctl(g1, &"g1", RoomControl.Kind.TOGGLE, RoomControl.Scope.STUDIO, &"ceiling")
	_ctl(g2, &"g2", RoomControl.Kind.TOGGLE, RoomControl.Scope.STUDIO, &"ceiling")
	var reg := RoomControlRegistry.collect(root)
	check("три управления (лампа, ползунок, группа)", reg.defs.size() == 3, str(reg.defs.size()))
	check("замечаний нет", reg.warnings.is_empty(), str(reg.warnings))
	var d_lamp := reg.by_id(&"lamp_a")
	check("лампа: включена по умолчанию", d_lamp != null and lamp.visible and is_equal_approx(lamp.light_energy, 80.0))
	d_lamp.set_value(0.0)
	check("лампа: выключена", not lamp.visible and d_lamp.value == 0.0)
	d_lamp.set_value(0.7)
	check("лампа: TOGGLE любое значение выше нуля это вкл, энергия прежняя", lamp.visible and is_equal_approx(lamp.light_energy, 80.0) and d_lamp.value == 1.0)
	var d_dim := reg.by_id(&"dim")
	check("ползунок: по умолчанию 0.5 даёт энергию 25", is_equal_approx(dim.light_energy, 25.0) and dim.visible, str(dim.light_energy))
	d_dim.set_value(1.0)
	check("ползунок: 1 даёт энергию из сцены", is_equal_approx(dim.light_energy, 50.0))
	d_dim.set_value(0.0)
	check("ползунок: 0 гасит", not dim.visible)
	d_dim.set_value(0.4)
	check("ползунок возвращается без накопления ошибки", is_equal_approx(dim.light_energy, 20.0), str(dim.light_energy))
	var grp := reg.by_id(&"ceiling")
	check("группа: один управляемый объект на два узла", grp != null and grp.nodes.size() == 2 and reg.by_id(&"g1") == null)
	grp.set_value(0.0)
	check("группа: оба света выключаются разом", not g1.visible and not g2.visible)
	check("for_scope: Observe только лампа", reg.for_scope(RoomControl.Scope.OBSERVE).size() == 1 and reg.for_scope(RoomControl.Scope.STUDIO).size() == 2)
	reg.reset()
	check("reset: значения по умолчанию", lamp.visible and is_equal_approx(dim.light_energy, 25.0) and g1.visible and g2.visible)

	print("== 2. Механизмы SLIDE, ROTATE")
	var root2 := Node3D.new()
	add_child(root2)
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(5, 0, 0)
	root2.add_child(door)
	_ctl(door, &"door", RoomControl.Kind.MECH, RoomControl.Scope.STUDIO, &"", _mech(MechanismConfig.Actuator.SLIDE, &"door", Vector3.RIGHT, 10.0), 0.0)
	var flap := Node3D.new()
	flap.name = "Flap"
	root2.add_child(flap)
	_ctl(flap, &"flap", RoomControl.Kind.MECH, RoomControl.Scope.STUDIO, &"", _mech(MechanismConfig.Actuator.ROTATE, &"flap", Vector3.UP, 90.0), 0.0)
	var reg2 := RoomControlRegistry.collect(root2)
	check("два механизма", reg2.defs.size() == 2 and reg2.warnings.is_empty(), str(reg2.warnings))
	check("SLIDE: в покое на месте", is_equal_approx(door.position.x, 5.0))
	reg2.by_id(&"door").set_value(1.0, true)
	check("SLIDE: состояние 1 сдвигает на travel", is_equal_approx(door.position.x, 15.0), str(door.position))
	reg2.by_id(&"door").set_value(0.0, true)
	check("SLIDE: обратно", is_equal_approx(door.position.x, 5.0))
	reg2.by_id(&"flap").set_value(1.0, true)
	check("ROTATE: состояние 1 поворачивает на travel", absf(absf(flap.rotation_degrees.y) - 90.0) < 0.01, str(flap.rotation_degrees))
	var d_door := reg2.by_id(&"door")
	d_door.set_value(1.0, false)
	check("ход по времени: цель задана, ещё не дошёл", d_door.is_moving() and is_equal_approx(door.position.x, 5.0))
	reg2.tick(0.5)
	check("ход по времени: середина (duration 1 с)", door.position.x > 5.0 and door.position.x < 15.0, str(door.position.x))
	reg2.tick(0.6)
	check("ход по времени: пришёл", not d_door.is_moving() and is_equal_approx(door.position.x, 15.0) and is_equal_approx(d_door.value, 1.0))

	print("== 3. Механизм ANIM по анимации mech_<id>")
	var root3 := Node3D.new()
	add_child(root3)
	var blind := Node3D.new()
	blind.name = "Blind"
	root3.add_child(blind)
	var player := AnimationPlayer.new()
	player.name = "Anim"
	root3.add_child(player)
	var anim := Animation.new()
	var ti := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(ti, NodePath("Blind"))
	anim.position_track_insert_key(ti, 0.25, Vector3.ZERO)
	anim.position_track_insert_key(ti, 1.25, Vector3(0, 40, 0))
	var lib := AnimationLibrary.new()
	lib.add_animation(&"mech_blind", anim)
	player.add_animation_library(&"", lib)
	_ctl(player, &"blind", RoomControl.Kind.MECH, RoomControl.Scope.OBSERVE, &"", _mech(MechanismConfig.Actuator.ANIM, &"blind"), 0.0)
	var reg3 := RoomControlRegistry.collect(root3)
	check("ANIM привязан к плееру", reg3.defs.size() == 1 and reg3.warnings.is_empty(), str(reg3.warnings))
	var d_blind := reg3.by_id(&"blind")
	d_blind.set_value(1.0, true)
	check("ANIM: состояние 1 это последний ключ", is_equal_approx(blind.position.y, 40.0), str(blind.position))
	d_blind.set_value(0.5, true)
	check("ANIM: состояние 0.5 это середина времени ключей", is_equal_approx(blind.position.y, 20.0), str(blind.position))
	d_blind.set_value(0.0, true)
	check("ANIM: состояние 0 это первый ключ (не нулевое время)", is_equal_approx(blind.position.y, 0.0))

	print("== 4. Ошибки: замечания, а не падение")
	var root4 := Node3D.new()
	add_child(root4)
	var a := _light(root4, "A", 10.0)
	var b := _light(root4, "B", 10.0)
	_ctl(a, &"same")
	_ctl(b, &"same")
	var plain := Node3D.new()
	plain.name = "Plain"
	root4.add_child(plain)
	_ctl(plain, &"bad_slider", RoomControl.Kind.SLIDER)
	var nomesh := Node.new()
	nomesh.name = "NotNode3D"
	root4.add_child(nomesh)
	_ctl(nomesh, &"bad_toggle")
	_ctl(a, &"")
	var no_anim := Node3D.new()
	no_anim.name = "NoAnim"
	root4.add_child(no_anim)
	_ctl(no_anim, &"no_anim", RoomControl.Kind.MECH, RoomControl.Scope.STUDIO, &"", _mech(MechanismConfig.Actuator.ANIM, &"no_anim"))
	var reg4 := RoomControlRegistry.collect(root4)
	check("повтор id: одно управление и замечание", reg4.by_id(&"same") != null and reg4.by_id(&"same").nodes.size() == 1 and _has(reg4, "повтор id"), str(reg4.warnings))
	check("SLIDER на Node3D не создан", reg4.by_id(&"bad_slider") == null)
	check("TOGGLE на Node не создан", reg4.by_id(&"bad_toggle") == null)
	check("метка без id: замечание", _has(reg4, "без id"))
	check("ANIM без анимации не создан", reg4.by_id(&"no_anim") == null)
	check("для каждого отказа есть замечание", reg4.warnings.size() >= 5, str(reg4.warnings.size()))
	check("рабочее управление осталось", reg4.defs.size() == 1)

	print("== 5. Метки в настоящей сцене attic")
	var attic := (load("res://data/models/room_attic/room_attic.tscn") as PackedScene).instantiate()
	add_child(attic)
	var reg5 := RoomControlRegistry.collect(attic, "attic")
	check("в attic две лампы с метками", reg5.defs.size() == 2 and reg5.warnings.is_empty(), "%d %s" % [reg5.defs.size(), reg5.warnings])
	check("lamp_1 для Observe, lamp_2 только студия",
			reg5.by_id(&"lamp_1") != null and reg5.by_id(&"lamp_1").scope == RoomControl.Scope.OBSERVE
			and reg5.by_id(&"lamp_2") != null and reg5.by_id(&"lamp_2").scope == RoomControl.Scope.STUDIO)
	var l1 := reg5.by_id(&"lamp_1").nodes[0] as Light3D
	reg5.by_id(&"lamp_1").set_value(0.0)
	check("lamp_1 гасит Lamp0", not l1.visible and l1.name == "Lamp0")
	attic.queue_free()

	for n in [root, root2, root3, root4]:
		n.queue_free()
	await get_tree().process_frame
	print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)


func _has(reg: RoomControlRegistry, part: String) -> bool:
	for w in reg.warnings:
		if part in w:
			return true
	return false
