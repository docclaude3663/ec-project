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
	if k.keycode == KEY_PAGEUP:
		return BIG_STEP
	if k.keycode == KEY_PAGEDOWN:
		return -BIG_STEP
	if k.shift_pressed:
		if k.keycode == KEY_R or k.physical_keycode == KEY_R:
			return BIG_STEP
		if k.keycode == KEY_F or k.physical_keycode == KEY_F:
			return -BIG_STEP
	return 0
