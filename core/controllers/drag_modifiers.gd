class_name DragModifiers extends Node

# XX claude-switch (новый файл)
#########################
## Модификаторы драга: Alt вращает объект, Ctrl меняет его высоту. Общая часть для DragTool и BuildTool (призрак на курсоре).
#########################
## Пока модификатор зажат, курсор прячется и замораживается (MOUSE_MODE_CAPTURED), объект стоит на месте, а мышь управляет параметром:
##  - Alt:  горизонтальное смещение мыши вращает объект вокруг Y (on_rotate_input), вправо мышью = вправо. Shift: точнее.
##          Лист террейна Alt не вращает: у него Alt уже занят («без магнита», ATTN_13).
##  - Ctrl: вертикальное смещение мыши меняет уровень (on_elevation_input, как R/F): вверх = выше. Один уровень на PX_PER_LEVEL пикселей.
## Отпустили модификатор: курсор снова виден и возвращается в точку, где был нажат модификатор, поэтому объект не дергается.
## Объект на время модификатора стоит на замороженном вводе курсора (remember): мы повторяем с ним on_drag_moved после каждого изменения,
## потому что поворот и уровень только меняют состояние объекта, а трансформ применяется событием on_drag_moved.
## Относительное смещение мыши берем из InputEventMouseMotion.relative (в режиме CAPTURED позиция курсора не меняется).
## Вызывать tick() каждый кадр из process_tick инструмента, remember() в обычном кадре, reset() при входе и выходе из инструмента.
## Узел должен быть в дереве (инструмент добавляет его себе дочерним в _ready).
## Модификаторы читаются через Actions (alt, ctrl, shift), как в остальных инструментах (U6.1).
## BuildTool не зовет tick(), пока рисуется полигон или полоса листа: там Ctrl+R/F это толщина, а Alt лист не вращает.

const DEG_PER_PX := 0.5
const DEG_PER_PX_FINE := 0.1
const PX_PER_LEVEL := 20.0

enum Mode { NONE, ROTATE, HEIGHT }

var _mode: Mode = Mode.NONE
var _viewport: Viewport
var _saved_pos := Vector2.ZERO    # где был курсор, когда нажали модификатор
var _acc := Vector2.ZERO          # накопленное смещение мыши с прошлого кадра
var _level_acc := 0.0             # накопленные пиксели высоты
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE   # режим мыши до модификатора: его и вернем
var _frozen: Dictionary = {}      # последний ввод курсора (hit) до модификатора: позиция, на которой объект стоит


func _input(event: InputEvent) -> void:
	if _mode != Mode.NONE and event is InputEventMouseMotion:
		_acc += event.relative


func _notification(what: int) -> void:
	# Окно потеряло фокус или узел уходит: вернуть курсор, иначе он останется скрытым
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_end()


## Вход и выход из инструмента: вернуть курсор, забыть замороженный ввод
func reset() -> void:
	_end()
	_frozen = {}


## Обычный кадр: запомнить ввод курсора, с которым объект сейчас стоит
func remember(hit: Dictionary) -> void:
	_frozen = hit.duplicate()


## Возвращает true, пока модификатор зажат: инструмент в этом кадре позицию объекта не обновляет
func tick(target: Entity, viewport: Viewport) -> bool:
	if target == null or not is_instance_valid(target):
		_end()
		return false
	# Объект еще не стоял ни на одной позиции курсора (модификатор зажат с самого входа в инструмент): сначала один обычный кадр,
	# иначе повторять on_drag_moved нечем и поворот или уровень не видны до отпускания
	if _mode == Mode.NONE and _frozen.is_empty():
		return false
	var want := Mode.NONE
	if Actions.alt() and not target.has_comp(C_TerrainLayer):
		want = Mode.ROTATE
	elif Actions.ctrl():
		want = Mode.HEIGHT
	if want != _mode:
		_end()
		if want != Mode.NONE:
			_begin(want, viewport)
	if _mode == Mode.NONE:
		return false
	_apply(target)
	return true


func _begin(mode: Mode, viewport: Viewport) -> void:
	_mode = mode
	_viewport = viewport
	_saved_pos = viewport.get_mouse_position()
	_acc = Vector2.ZERO
	_level_acc = 0.0
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end() -> void:
	if _mode == Mode.NONE:
		return
	_mode = Mode.NONE
	Input.mouse_mode = _prev_mouse_mode
	# Курсор возвращаем туда, где его заморозили (из координат viewport в координаты окна)
	if _viewport != null and is_instance_valid(_viewport):
		Input.warp_mouse(_viewport.get_screen_transform() * _saved_pos)
	_viewport = null
	_acc = Vector2.ZERO


func _apply(target: Entity) -> void:
	var changed := false
	match _mode:
		Mode.ROTATE:
			var dx := _acc.x
			_acc = Vector2.ZERO
			if absf(dx) > 0.0:
				var k := DEG_PER_PX_FINE if Actions.shift() else DEG_PER_PX
				target.send_event("on_rotate_input", {"axis": "y", "amount": dx * k})
				changed = true
		Mode.HEIGHT:
			_level_acc += -_acc.y   # мышь вверх (relative.y < 0) поднимает объект
			_acc = Vector2.ZERO
			var steps := int(_level_acc / PX_PER_LEVEL)   # к нулю: целые уровни
			if steps != 0:
				_level_acc -= steps * PX_PER_LEVEL
				target.send_event("on_elevation_input", {"levels": steps})
				changed = true
	# Применить изменение на прежней позиции
	if changed and not _frozen.is_empty():
		target.send_event("on_drag_moved", _frozen.duplicate())
