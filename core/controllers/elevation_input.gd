class_name ElevationInput extends RefCounted

# XX claude-terra 13.1.4 (новый файл)
#######################
## Хелпер тулов. Крупный шаг уровня: Shift+R / Shift+F и PageUp / PageDown.
#######################
## Обычные R / F (один слой) остаются в BuildTool и DragTool как были. Здесь только крупный шаг:
## BuildTool и DragTool шлют цели событие "on_elevation_input" {"levels": int}.
## Реагируют C_TrackDraggable, C_TerrainDraggable и C_FlexShape (в фазе конца).
## Событие разовое (не echo), чтобы один нажим давал один шаг, сколько бы InputEvent ни пришло за кадр.

## Крупный шаг, слоёв. Для моста над траком с вагоном нужно около 7 слоёв: Shift+R и ещё два R
const BIG_STEP := 5


## Слои для события клавиши или 0, если это не крупный шаг уровня
static func levels_from_event(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return 0
	if k.is_action(&"level_up_x5"):
		return BIG_STEP
	if k.is_action(&"level_down_x5"):
		return -BIG_STEP
	if k.shift_pressed:
		if k.is_action(&"level_up"):
			return BIG_STEP
		if k.is_action(&"level_down"):
			return -BIG_STEP
	return 0


## Шаг для инструментов, где R/F и PgUp/PgDn работают сразу (рельеф, рисование листа): ±1 (R/F), ±5 (Shift+R/F, PgUp/PgDn).
## 0, если это не клавиша уровня. Ctrl не учитывается: глубину по Ctrl ловит depth_from_event раньше
static func step_from_event(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return 0
	if k.is_action(&"level_up_x5"):
		return BIG_STEP
	if k.is_action(&"level_down_x5"):
		return -BIG_STEP
	return Actions.axis_step(event, &"level_up", &"level_down", BIG_STEP)


## Шаг глубины (толщины): Ctrl+R/F ±1, Ctrl+Shift+R/F и Ctrl+PgUp/PgDn ±5. 0, если это не она
static func depth_from_event(event: InputEvent) -> int:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return 0
	var n := Actions.axis_step(event, &"depth_up", &"depth_down", BIG_STEP)
	if n != 0:
		return n
	if k.ctrl_pressed:
		if k.is_action(&"level_up_x5"):
			return BIG_STEP
		if k.is_action(&"level_down_x5"):
			return -BIG_STEP
	return 0
