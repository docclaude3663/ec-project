class_name AltRotate extends RefCounted

# XX claude-switch (новый файл)
#########################
## Вращение объекта по Alt + движение мыши. Общая часть для DragTool (перетаскивание) и BuildTool (призрак на курсоре).
#########################
## Пока Alt зажат, горизонтальное движение мыши поворачивает объект вокруг Y (событие on_rotate_input, как Q/E, но плавно),
## а позиция объекта не обновляется: инструмент в это время не шлет on_drag_moved. Отпустили Alt: объект снова идет за курсором.
## Shift: точнее (DEG_PER_PX_FINE). Объект поворачивается вслед за движением мыши (вправо мышью = вправо). Знак подобран по проверке в редакторе:
## первая версия (-dx) вращала в обратную сторону.
## Исключение: лист террейна. Для него Alt уже занят («без магнита», ATTN_13), поэтому его Alt не вращает.
## Вызывать tick() каждый кадр из process_tick инструмента, а в обычном кадре (Alt не зажат) передавать последний ввод курсора в remember().
## Поворот только меняет состояние объекта, а трансформ применяется событием on_drag_moved. Поэтому на время Alt мы повторяем последний
## on_drag_moved со ЗАМОРОЖЕННЫМ вводом (позиция та же, поворот новый): объект стоит на месте и виден повернутым сразу, а не после отпускания Alt.

const DEG_PER_PX := 0.5
const DEG_PER_PX_FINE := 0.1

var _active := false
var _last_x := 0.0
var _frozen: Dictionary = {}   # последний ввод курсора (hit) до Alt: позиция, на которой объект стоит


func reset() -> void:
	_active = false
	_frozen = {}


## Обычный кадр: запомнить ввод курсора, с которым объект сейчас стоит
func remember(hit: Dictionary) -> void:
	_frozen = hit.duplicate()


## Возвращает true, пока Alt зажат и объект вращается: инструмент в этом кадре позицию объекта не трогает
func tick(target: Entity, viewport: Viewport) -> bool:
	if target == null or not is_instance_valid(target) or target.has_comp(C_TerrainLayer):
		_active = false
		return false
	if not Actions.alt():
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
		var k := DEG_PER_PX_FINE if Actions.shift() else DEG_PER_PX
		target.send_event("on_rotate_input", {"axis": "y", "amount": dx * k})
		# Применить новый поворот на прежней позиции
		if not _frozen.is_empty():
			target.send_event("on_drag_moved", _frozen.duplicate())
	return true
