class_name AltRotate extends RefCounted

# XX claude-switch (новый файл)
#########################
## Вращение объекта по Alt + движение мыши. Общая часть для DragTool (перетаскивание) и BuildTool (призрак на курсоре).
#########################
## Пока Alt зажат, горизонтальное движение мыши поворачивает объект вокруг Y (событие on_rotate_input, как Q/E, но плавно),
## а позиция объекта не обновляется: инструмент в это время не шлет on_drag_moved. Отпустили Alt: объект снова идет за курсором.
## Shift: точнее (DEG_PER_PX_FINE). Вправо = по часовой стрелке (вид сверху).
## Исключение: лист террейна. Для него Alt уже занят («без магнита», ATTN_13), поэтому его Alt не вращает.
## Вызывать tick() каждый кадр из process_tick инструмента.

const DEG_PER_PX := 0.5
const DEG_PER_PX_FINE := 0.1

var _active := false
var _last_x := 0.0


func reset() -> void:
	_active = false


## Возвращает true, пока Alt зажат и объект вращается: инструмент в этом кадре позицию объекта не трогает
func tick(target: Entity, viewport: Viewport) -> bool:
	if target == null or not is_instance_valid(target) or target.has_comp(C_TerrainLayer):
		_active = false
		return false
	if not Input.is_key_pressed(KEY_ALT):
		_active = false
		return false
	var x := viewport.get_mouse_position().x
	if not _active:
		_active = true
		_last_x = x   # первый кадр: запоминаем курсор, чтобы объект не дернулся
		return true
	var dx := x - _last_x
	_last_x = x
	if absf(dx) > 0.0:
		var k := DEG_PER_PX_FINE if Input.is_key_pressed(KEY_SHIFT) else DEG_PER_PX
		target.send_event("on_rotate_input", {"axis": "y", "amount": -dx * k})
	return true
