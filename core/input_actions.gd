extends Node
# class_name не задаём: это синглтон Actions (autoload)

###########################
## Actions: реестр игровых действий (ATTN_17 §17.7, U6.1, решение D14)
###########################
## Одна запись описывает действие: id, ключ локализации названия, группа, контексты и клавиша по умолчанию.
## Окно ремапа (U11) и подсказки (U6.3) строятся из реестра, новые действия добавляются одной строкой в DEFAULTS.
##
## Контекст: где действие живёт (global, build, select, drag, terrain_tools, observe, debug).
## Одна клавиша может стоять в разных контекстах (законный повтор), конфликтом считается только повтор
## внутри одного контекста, а также повтор с действием контекста global (оно действует везде).
##
## Модификаторы (Shift, Ctrl, Alt) не переназначаются: инструменты читают их через shift(), ctrl(), alt().
## Сочетания с мышью (Shift+ЛКМ, Ctrl+ЛКМ) остаются как есть.
##
## Действия, которые уже есть в Project Settings -> Input Map, берутся оттуда (клавиша по умолчанию = то, что записано
## в project.godot). Остальные заводятся здесь кодом. Переопределения игрока лежат в Settings, секция [input].

const SECTION := "input"
## Число закладок камеры Observe (ObserveCameraRig.BOOKMARK_COUNT), действия bookmark_1 ... bookmark_N
const BOOKMARK_COUNT := 5

const G_GLOBAL := &"global"
const G_BUILD := &"build"
const G_SELECT := &"select"
const G_DRAG := &"drag"
const G_TERRAIN := &"terrain_tools"
const G_OBSERVE := &"observe"
const G_DEBUG := &"debug"

## id -> {id, title_key, group, contexts: Array, defaults: Array[InputEvent], remappable: bool}
var _entries: Dictionary = {}
## Порядок регистрации (для окна ремапа)
var _order: Array[StringName] = []

signal binding_changed(id: StringName)


func _ready() -> void:
	_register_defaults()
	_apply_overrides()


## Таблица действий. Колонки: id, title_key, group, contexts, клавиша по умолчанию, можно ли переназначать.
## Клавиша = физическая (раскладка не важна). Если действие уже есть в project.godot, колонка клавиши игнорируется.
func _register_defaults() -> void:
	# Повороты и уровень: Build и Drag
	register(&"rotate_left", "action.rotate_left", &"build", [G_BUILD, G_DRAG], _key(KEY_Q))
	register(&"rotate_right", "action.rotate_right", &"build", [G_BUILD, G_DRAG], _key(KEY_E))
	# R/F и PgUp/PgDn: уровень. В инструментах рельефа то же по смыслу (плоскость выреза, глубина воды, уровень листа)
	register(&"level_up", "action.level_up", &"build", [G_BUILD, G_DRAG, G_TERRAIN], _key(KEY_R))
	register(&"level_down", "action.level_down", &"build", [G_BUILD, G_DRAG, G_TERRAIN], _key(KEY_F))
	register(&"level_up_x5", "action.level_up_x5", &"build", [G_BUILD, G_DRAG, G_TERRAIN], _key(KEY_PAGEUP))
	register(&"level_down_x5", "action.level_down_x5", &"build", [G_BUILD, G_DRAG, G_TERRAIN], _key(KEY_PAGEDOWN))
	register(&"duplicate_last", "action.duplicate_last", &"build", [G_BUILD, G_SELECT], _key(KEY_V))
	register(&"flex_limits_toggle", "action.flex_limits_toggle", &"build", [G_BUILD], _key(KEY_L))
	register(&"flex_zones_toggle", "action.flex_zones_toggle", &"build", [G_BUILD], _key(KEY_Z))
	register(&"tunnel_toggle", "action.tunnel_toggle", &"build", [G_BUILD, G_SELECT], _key(KEY_U))
	# Select
	register(&"delete", "action.delete", &"select", [G_SELECT], _key(KEY_DELETE))
	register(&"embankment_toggle", "action.embankment_toggle", &"select", [G_SELECT], _key(KEY_B))
	register(&"wagon_kick_fwd", "action.wagon_kick_fwd", &"select", [G_SELECT], _key(KEY_PAGEUP))
	register(&"wagon_kick_back", "action.wagon_kick_back", &"select", [G_SELECT], _key(KEY_PAGEDOWN))
	register(&"switch_throw", "action.switch_throw", &"select", [G_SELECT], _key(KEY_T))
	# Drag
	register(&"reset_transform", "action.reset_transform", &"drag", [G_DRAG], _key(KEY_HOME))
	# Инструменты рельефа и рисование листа (ATTN_13 §13.11). Смысл одинаков во всех: подтвердить, отменить шаг, ширина, глубина
	register(&"shape_confirm", "action.shape_confirm", &"terrain", [G_TERRAIN], [_key(KEY_ENTER), _key(KEY_KP_ENTER)])
	register(&"shape_undo", "action.shape_undo", &"terrain", [G_TERRAIN], _key(KEY_BACKSPACE))
	register(&"width_down", "action.width_down", &"terrain", [G_TERRAIN], _key(KEY_BRACKETLEFT))
	register(&"width_up", "action.width_up", &"terrain", [G_TERRAIN], _key(KEY_BRACKETRIGHT))
	register(&"depth_up", "action.depth_up", &"terrain", [G_TERRAIN], _key(KEY_R, false, true))
	register(&"depth_down", "action.depth_down", &"terrain", [G_TERRAIN], _key(KEY_F, false, true))
	register(&"cut_through", "action.cut_through", &"terrain", [G_TERRAIN], _key(KEY_END))
	register(&"tool_undo", "action.tool_undo", &"terrain", [G_TERRAIN], _key(KEY_Z, false, true))
	# Observe
	register(&"photo_hide_ui", "action.photo_hide_ui", &"observe", [G_OBSERVE], _key(KEY_H))
	register(&"photo_snap", "action.photo_snap", &"observe", [G_OBSERVE], _key(KEY_P))
	register(&"observe_cancel", "action.observe_cancel", &"observe", [G_OBSERVE], _key(KEY_ESCAPE), false)
	for i in BOOKMARK_COUNT:
		# Ctrl+цифра сохраняет закладку (модификатор читается инструментом, не переназначается)
		register(StringName("bookmark_%d" % (i + 1)), "action.bookmark", &"observe", [G_OBSERVE], _key((KEY_1 + i) as Key))
	# Общие
	register(&"quick_save", "action.quick_save", &"system", [G_GLOBAL], _key(KEY_S, false, true))
	# Отладка
	register(&"debug_panel_toggle", "action.debug_panel_toggle", &"debug", [G_DEBUG], _key(KEY_F3))
	register(&"debug_vsync_toggle", "action.debug_vsync_toggle", &"debug", [G_DEBUG], _key(KEY_V, true, true))
	# F7 читает модификаторы сам: Shift, Alt, Ctrl задают вид выреза (c_terrain_layer), поэтому читается не точно
	register(&"debug_stats_toggle", "action.debug_stats_toggle", &"debug", [G_DEBUG], _key(KEY_F4))
	register(&"debug_terrain_probe", "action.debug_terrain_probe", &"debug", [G_DEBUG], _key(KEY_F7))
	register(&"debug_load_reference", "action.debug_load_reference", &"debug", [G_DEBUG], _key(KEY_F9))
	register(&"debug_save_look", "action.debug_save_look", &"debug", [G_DEBUG], _key(KEY_F10))
	register(&"debug_look_lab", "action.debug_look_lab", &"debug", [G_DEBUG], _key(KEY_L, true, true))
	register(&"debug_look_lab_medium", "action.debug_look_lab_medium", &"debug", [G_DEBUG], _key(KEY_M, true, true))
	register(&"debug_look_lab_low", "action.debug_look_lab_low", &"debug", [G_DEBUG], _key(KEY_K, true, true))
	register(&"debug_look_matrix", "action.debug_look_matrix", &"debug", [G_DEBUG], _key(KEY_N, true, true))
	register(&"debug_look_matrix_medium", "action.debug_look_matrix_medium", &"debug", [G_DEBUG], _key(KEY_B, true, true))
	register(&"debug_look_matrix_low", "action.debug_look_matrix_low", &"debug", [G_DEBUG], _key(KEY_J, true, true))
	# Механизмы выбранного вагона (временно, до вкладки в InfoPanel)
	register(&"mechanisms_toggle", "action.mechanisms_toggle", &"debug", [G_DEBUG], _key(KEY_O))
	register(&"lights_toggle", "action.lights_toggle", &"debug", [G_DEBUG], _key(KEY_I))
	register(&"mechanisms_gizmos", "action.mechanisms_gizmos", &"debug", [G_DEBUG], _key(KEY_I, true))
	# Камера: файлы камеры не трогаем, действия описаны как есть (U6, решения этапа)
	register(&"key_w", "action.camera_forward", &"camera", [G_GLOBAL], _key(KEY_W))
	register(&"key_s", "action.camera_back", &"camera", [G_GLOBAL], _key(KEY_S))
	register(&"key_a", "action.camera_left", &"camera", [G_GLOBAL], _key(KEY_A))
	register(&"key_d", "action.camera_right", &"camera", [G_GLOBAL], _key(KEY_D))
	# Мышь: описаны для справки, не переназначаются
	register(&"lmb", "action.mouse_left", &"mouse", [G_GLOBAL], null, false)
	register(&"rmb", "action.mouse_right", &"mouse", [G_GLOBAL], null, false)
	register(&"mmb", "action.mouse_middle", &"mouse", [G_GLOBAL], null, false)
	register(&"mouse_wheel_up", "action.mouse_wheel_up", &"mouse", [G_GLOBAL], null, false)
	register(&"mouse_wheel_down", "action.mouse_wheel_down", &"mouse", [G_GLOBAL], null, false)
	# Резерв: действия есть в Input Map, в коде не используются (ATTN_13 §13.11 резервирует key_g)
	register(&"key_g", "action.reserved_g", &"reserved", [G_GLOBAL], null, false)
	register(&"key_num_5", "action.reserved_num5", &"reserved", [G_GLOBAL], null, false)
	register(&"key_shift_l", "action.reserved_shift_l", &"reserved", [G_GLOBAL], null, false)


## Регистрация действия. default_event (одно событие или массив) используется, только если в InputMap действия ещё нет.
func register(id: StringName, title_key: String, group: StringName, contexts: Array,
		default_event: Variant = null, remappable := true) -> void:
	if _entries.has(id):
		push_warning("Actions: действие %s уже зарегистрировано" % id)
		return
	if not InputMap.has_action(id):
		InputMap.add_action(id)
		var events: Array = default_event if default_event is Array else ([default_event] if default_event else [])
		for ev in events:
			InputMap.action_add_event(id, ev)
	_entries[id] = {
		"id": id,
		"title_key": title_key,
		"group": group,
		"contexts": contexts.duplicate(),
		"defaults": _copy_events(id),
		"remappable": remappable,
	}
	_order.append(id)
	var clash := find_conflict(id, null)
	if clash != &"":
		push_warning("Actions: %s и %s на одной клавише в одном контексте" % [id, clash])


func has(id: StringName) -> bool:
	return _entries.has(id)


## Все записи реестра в порядке регистрации (для окна ремапа)
func get_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _order:
		out.append(_entries[id])
	return out


## Действие по событию. Модификаторы должны совпасть точно: Ctrl+V не сработает как V, Shift+R не как R
func pressed(event: InputEvent, id: StringName) -> bool:
	return event.is_action_pressed(id, false, true)


## Шаг по паре действий «больше, меньше»: +n или -n, 0 если это не они. n = shift_mult при зажатом Shift, иначе 1.
## Модификаторы не проверяются точно (Shift и Ctrl читает вызывающий). Для инструментов, где одна клавиша шагает значение
func axis_step(event: InputEvent, up: StringName, down: StringName, shift_mult := 1) -> int:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return 0
	var n := shift_mult if (shift_mult > 1 and k.shift_pressed) else 1
	if k.is_action(up):
		return n
	if k.is_action(down):
		return -n
	return 0


func shift() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


func ctrl() -> bool:
	return Input.is_key_pressed(KEY_CTRL)


func alt() -> bool:
	return Input.is_key_pressed(KEY_ALT)


## Подпись клавиши действия для подсказок («R», «Ctrl+S»). Пусто, если клавиши нет
func key_text(id: StringName) -> String:
	if not InputMap.has_action(id):
		return ""
	for ev in InputMap.action_get_events(id):
		var k := ev as InputEventKey
		if k:
			var code := k.get_physical_keycode_with_modifiers() if k.physical_keycode != KEY_NONE \
					else k.get_keycode_with_modifiers()
			return _pretty(OS.get_keycode_string(code))
	return ""


## Короткие названия для подсказок: PageUp → PgUp, BackSpace → Backspace, Escape → Esc, BracketLeft → [
func _pretty(text: String) -> String:
	var cut := text.rfind("+") + 1
	var key := text.substr(cut)
	var names := {"PageUp": "PgUp", "PageDown": "PgDn", "BackSpace": "Backspace", "Escape": "Esc", "Delete": "Del",
			"BracketLeft": "[", "BracketRight": "]", "QuoteLeft": "`"}
	return text.substr(0, cut) + names.get(key, key)


## Какое действие уже занимает эту клавишу в тех же контекстах. event == null: проверить текущую клавишу id.
## Возвращает &"" , если конфликта нет
func find_conflict(id: StringName, event: InputEvent) -> StringName:
	if not _entries.has(id):
		return &""
	var mine: Array = _entries[id].contexts
	var events: Array = [event] if event else InputMap.action_get_events(id)
	for other_id in _order:
		if other_id == id:
			continue
		var other: Dictionary = _entries[other_id]
		if not _contexts_overlap(mine, other.contexts):
			continue
		for ev in events:
			for oev in InputMap.action_get_events(other_id):
				if _same_key(ev, oev):
					return other_id
	return &""


## Назначить клавишу действию. Возвращает &"" при успехе или id действия, с которым конфликт (тогда ничего не меняется)
func set_binding(id: StringName, event: InputEventKey) -> StringName:
	if not _entries.has(id) or not _entries[id].remappable:
		return id
	var clash := find_conflict(id, event)
	if clash != &"":
		return clash
	_apply_key(id, event)
	Settings.set_value(SECTION, String(id), _to_dict(event))
	binding_changed.emit(id)
	return &""


## Вернуть клавишу по умолчанию
func reset_binding(id: StringName) -> void:
	if not _entries.has(id):
		return
	InputMap.action_erase_events(id)
	for ev in _entries[id].defaults:
		InputMap.action_add_event(id, ev.duplicate())
	Settings.erase_value(SECTION, String(id))
	binding_changed.emit(id)


func _apply_overrides() -> void:
	for id in _order:
		var entry: Dictionary = _entries[id]
		if not entry.remappable:
			continue
		# has_value заранее: get_value с дефолтом null пишет в консоль ошибку, если ключа нет
		if not Settings.has_value(SECTION, String(id)):
			continue
		var saved: Variant = Settings.get_value(SECTION, String(id), {})
		if saved is Dictionary and saved.has("key"):
			var ev := _from_dict(saved)
			# Сохранённая клавиша могла стать конфликтной (правили реестр): тогда остаётся клавиша по умолчанию
			if find_conflict(id, ev) == &"":
				_apply_key(id, ev)
			else:
				push_warning("Actions: сохранённая клавиша %s конфликтует, взята по умолчанию" % id)


func _copy_events(id: StringName) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(id):
		out.append(ev.duplicate())
	return out


func _apply_key(id: StringName, event: InputEventKey) -> void:
	InputMap.action_erase_events(id)
	InputMap.action_add_event(id, event)


func _contexts_overlap(a: Array, b: Array) -> bool:
	if a.has(G_GLOBAL) or b.has(G_GLOBAL):
		return true
	for c in a:
		if b.has(c):
			return true
	return false


func _same_key(a: InputEvent, b: InputEvent) -> bool:
	var ka := a as InputEventKey
	var kb := b as InputEventKey
	if ka == null or kb == null:
		return false
	return _code(ka) == _code(kb) and ka.get_modifiers_mask() == kb.get_modifiers_mask()


func _code(k: InputEventKey) -> int:
	return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode


func _key(code: Key, shift_mod := false, ctrl_mod := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.shift_pressed = shift_mod
	ev.ctrl_pressed = ctrl_mod
	return ev


func _to_dict(k: InputEventKey) -> Dictionary:
	return {"key": _code(k), "shift": k.shift_pressed, "ctrl": k.ctrl_pressed, "alt": k.alt_pressed}


func _from_dict(d: Dictionary) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = int(d.get("key", 0)) as Key
	ev.shift_pressed = bool(d.get("shift", false))
	ev.ctrl_pressed = bool(d.get("ctrl", false))
	ev.alt_pressed = bool(d.get("alt", false))
	return ev
