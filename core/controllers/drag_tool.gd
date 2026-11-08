class_name DragTool extends Node

#########################
## Инструмент перемещения(таскания)
#########################

var controller: ToolController
var target_entity: Entity

const ROT_STEP := 45.0 # Градусы
const ROT_FINE := 5.0 # Градусы, Shift+Q/E (XX claude-terra 13.1.7)

# Флаг позиции пкм
var rmb_pressed_pos := Vector2.ZERO

# XX claude-switch: вращение Alt + мышь (см. AltRotate)
var _alt_rotate := AltRotate.new()

# Группа на вечной сцепке тащится целиком: все части по порядку от головной, их {reversed, spacing},
# индекс схваченной и её положение относительно каждой (для свободного перетаскивания без рельс)
var _group: Array[Entity] = []
var _group_parts: Array[Dictionary] = []
var _group_index := -1
var _group_rel: Array[Transform3D] = []

## Начало драга
func enter():
	if not target_entity:
		controller.switch_tool(controller.select_tool)
		return

	_alt_rotate.reset()
	# Вешаем стейт (для визуала)
	target_entity.add_component(C_Drag.new())
	
	# Драг начался вот в этой точке
	var hit = controller.get_mouse_ray(Global.active_layers(['ground']))
	# Драг проверит, если евент из билд моде, то смещения мыши не будет
	#hit['build'] = false
	if hit.is_empty():
		# Курсор вне стола (спавн кнопкой с панели): стартуем драг по плоскости стола, иначе вагон не оживёт
		hit = controller.get_mouse_plane_hit()
	if hit:
		target_entity.send_event("on_drag_started", hit)
		_group_begin(hit)
		


# XX claude-terra
func _pick_mask() -> int:
	var identity := target_entity.get_comp(C_Identity) as C_Identity
	if identity and identity.setting:
		return Global.active_layers(identity.setting.get_pick_layers())
	return Global.active_layers(['ground','tracks','trains'])


## ⚡Сигнал(почти) о смене позиции в сущность. Там рзберется драгабл
func process_tick(_delta):
	# XX claude-switch: пока зажат Alt, объект вращается мышью, позицию не обновляем
	if _alt_rotate.tick(target_entity, controller.get_viewport()):
		return
	#var hit = controller.get_mouse_ray((1 << 0) | (1 << 2)|(1 << 4))
	var hit = controller.get_mouse_ray(_pick_mask())   # XX claude-terra слои из EntitySetting.pick_layers
	if hit:
		_alt_rotate.remember(hit)   # XX claude-switch: позиция, с которой объект стоит (нужна при вращении Alt)
		# Отправляем приказ в сущность. Оттуда C_TrackDraggable сам разберется.
		target_entity.send_event("on_drag_moved", hit)
		_group_move()
		pass



### Передача инпутов в ентити, tool_controller вызывает
func handle_input(event: InputEvent):
	# XX claude-terra 13.1.7: Shift+Q/E поворот на ROT_FINE (5°), без Shift ROT_STEP (45°)
	var _shift := Input.is_key_pressed(KEY_SHIFT)
	var _rot := ROT_FINE if _shift else ROT_STEP
	if Input.is_action_just_pressed("key_q"):
		target_entity.send_event("on_rotate_input", {"axis": "y", "amount": _rot})
	if Input.is_action_just_pressed("key_e"):
		target_entity.send_event("on_rotate_input", {"axis": "y", "amount": -_rot})
	# XX claude-terra 13.1.4: с Shift R/F идут крупным шагом через ElevationInput, обычный шаг без Shift
	if Input.is_action_just_pressed("key_r") and not _shift:
		target_entity.send_event("on_rotate_input", {"axis": "x", "amount": ROT_STEP})
	if Input.is_action_just_pressed("key_f") and not _shift:
		target_entity.send_event("on_rotate_input", {"axis": "x", "amount": -ROT_STEP})
	# XX claude-terra 13.1.4: Shift+R/F и PageUp/PageDown, крупный шаг уровня (трак, лист, вагон, 13.1.7)
	var _levels := ElevationInput.levels_from_event(event)
	if _levels != 0:
		target_entity.send_event("on_elevation_input", {"levels": _levels})
	if Input.is_action_just_pressed("ui_home"):
		target_entity.send_event("on_drag_reset", {}) # сбросить состояние
	# 13.1.7: PageUp/PageDown теперь крупный шаг уровня (ElevationInput выше) для всех, и для вагона тоже
		
	if Input.is_action_just_released("lmb"):
		controller.switch_tool(controller.select_tool)# Драг окончен дропом
	
	#  ПКМ 
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed: # нажали 
			rmb_pressed_pos = event.position
		else: # отпустили
			# Отменяем драг режим если это был короткий клик (не драг камеры)
			if rmb_pressed_pos.distance_to(event.position) < 5:
				controller.switch_tool(controller.select_tool)


## Драг окончен
func exit(_to_drag : bool = false):
	
	if target_entity:
		target_entity.remove_component(C_Drag)
		target_entity.send_event("on_drag_ended", {})
		_group_end()


## Схваченный вагон на вечной сцепке: берём всю группу, остальным частям тоже драг (связи между ними не рвутся)
func _group_begin(hit: Dictionary) -> void:
	_group_clear()
	var coupler := target_entity.get_comp(C_Coupler) as C_Coupler
	if coupler == null:
		return
	var chain := coupler.get_ordered_consist(true)
	if chain.size() < 2:
		return
	var start := target_entity.global_transform
	var prev: Entity = null
	for i in chain.size():
		var e: Entity = chain[i]["entity"]
		_group.append(e)
		_group_parts.append({
			"reversed": chain[i]["reversed"],
			"spacing": 0.0 if prev == null else prev.global_position.distance_to(e.global_position),
		})
		_group_rel.append(start.affine_inverse() * e.global_transform)
		if e == target_entity:
			_group_index = i
		else:
			e.add_component(C_Drag.new())
			e.send_event("on_drag_started", hit)
		prev = e


## Посадка схваченной части на трак: пусто, если она не на рельсах
func _group_snap() -> Dictionary:
	var dr := target_entity.get_comp(C_TrainDraggable) as C_TrainDraggable
	if dr == null or not dr.is_snapped_to_track or not is_instance_valid(dr.current_track):
		return {}
	return {"track": dr.current_track, "offset": dr.current_curve_point, "route": dr.current_route}


## Части группы за схваченной: по пути, если она на рельсах и группа помещается, иначе жёстко за ней
func _group_move() -> void:
	if _group.size() < 2:
		return
	var states: Array[Dictionary] = ConsistPlacer.plan_parts(_group_parts, _group_index, target_entity, _group_snap())
	for i in _group.size():
		var e := _group[i]
		if i == _group_index or not is_instance_valid(e):
			continue
		if states.is_empty():
			e.global_transform = target_entity.global_transform * _group_rel[i]
		else:
			ConsistPlacer.pose(e, _group_parts[i], states[i])


## Дроп: остальные части получают конец драга, группа садится на рельсы вслед за схваченной
func _group_end() -> void:
	if _group.size() >= 2:
		for e in _group:
			if e != target_entity and is_instance_valid(e):
				e.send_event("on_drag_ended", {})
		var snap := _group_snap()
		if not snap.is_empty():
			ConsistPlacer.seat_group(_group, _group_parts, _group_index, snap)
		# C_Drag снимаем после посадки: пока он есть, вечные связи на паузе, а не рвутся
		for e in _group:
			if e != target_entity and is_instance_valid(e):
				e.remove_component(C_Drag)
	_group_clear()


func _group_clear() -> void:
	_group.clear()
	_group_parts.clear()
	_group_rel.clear()
	_group_index = -1
