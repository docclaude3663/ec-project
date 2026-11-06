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
		# Отправляем приказ в сущность. Оттуда C_TrackDraggable сам разберется.
		target_entity.send_event("on_drag_moved", hit)
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
