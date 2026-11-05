class_name DebugKeysTab extends DebugTab

###########################
## Вкладка «Keys»: отладочные клавиши (U14)
###########################
## Справочник клавиш, которые работают при Global.debug_mode. Кнопки у V-Sync, F9, F10 посылают нажатие клавиши
## в игру (удобно, когда F-клавиши заняты системой). F7 не посылается: ему нужен курсор над макетом.
## Список написан по коду: graphics_manager (Ctrl+Shift+V, F10), look_lab (Ctrl+Shift+L), save_manager (F9), terrain_manager и c_terrain_layer (F7),
## c_mechanisms (I), build_tool (L, Z). Появилась новая отладочная клавиша: добавить строку в KEYS.

## key: подпись клавиши; text: что делает; code: клавиша для кнопки (KEY_NONE: кнопки нет);
## action: действие InputMap для кнопки (если задано, кнопка шлет его, а не клавишу)
const KEYS: Array[Dictionary] = [
	{"key": "F3", "text": "Эта панель", "code": KEY_NONE},
	{"key": "F7", "text": "Печатает surface_y под курсором. С выбранным листом террейна: ниша; Shift: окно; Alt: тоннель; Ctrl: убрать последний вырез", "code": KEY_NONE},
	{"key": "Ctrl+Shift+V", "text": "V-Sync вкл/выкл (действие debug_vsync_toggle, переназначается в Project Settings). Раньше был F8, но в редакторе Godot это «Остановить игру»", "code": KEY_NONE, "action": &"debug_vsync_toggle"},
	{"key": "F9", "text": "Загрузить эталонную диораму (заменяет макет)", "code": KEY_F9},
	{"key": "F10", "text": "Сохранить встроенные Look и Time в .tres", "code": KEY_F10},
	{"key": "Ctrl+Shift+L", "text": "Look Lab, качество High: прогон вариантов Clean + Day по закладкам 1-5, снимки и метрики в user://look_lab/ (лучше в Observe, во время прогона ничего не трогать)", "code": KEY_NONE, "action": &"debug_look_lab"},
	{"key": "Ctrl+Shift+M", "text": "Look Lab, качество Medium (те же варианты, для сравнения fps и времени кадра)", "code": KEY_NONE, "action": &"debug_look_lab_medium"},
	{"key": "Ctrl+Shift+K", "text": "Look Lab, качество Low", "code": KEY_NONE, "action": &"debug_look_lab_low"},
	{"key": "Ctrl+Shift+N", "text": "Look Lab, матрица: все Look × все Time на текущих настройках, качество High (L4)", "code": KEY_NONE, "action": &"debug_look_matrix"},
	{"key": "Ctrl+Shift+B", "text": "Look Lab, матрица на Medium", "code": KEY_NONE, "action": &"debug_look_matrix_medium"},
	{"key": "Ctrl+Shift+J", "text": "Look Lab, матрица на Low", "code": KEY_NONE, "action": &"debug_look_matrix_low"},
	{"key": "I", "text": "У выбранного вагона: свет вкл/выкл; Shift+I: метки источников и размеры кузова в Output", "code": KEY_NONE},
	{"key": "L", "text": "Лимиты flex (в Build)", "code": KEY_NONE},
	{"key": "Z", "text": "Зоны проблем flex", "code": KEY_NONE},
]


func _init() -> void:
	name = &"Keys"
	add_child(make_note("Работают при Global.debug_mode (в редакторе и debug-сборке)."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 8)
	add_child(grid)
	for k in KEYS:
		var key := Label.new()
		key.text = k.key
		key.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key)
		var text := make_note(k.text)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(text)
		if k.has("action"):
			var send_a := Button.new()
			send_a.text = "Нажать"
			var action: StringName = k.action
			send_a.pressed.connect(func() -> void: _press_action(action))
			grid.add_child(send_a)
		elif k.code == KEY_NONE:
			grid.add_child(Control.new())
		else:
			var send := Button.new()
			send.text = "Нажать"
			var code: Key = k.code
			send.pressed.connect(func() -> void: _press(code))
			grid.add_child(send)


## Шлет действие InputMap (нажатие и отпускание)
func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)


## Шлет нажатие и отпускание клавиши как будто нажали на клавиатуре
func _press(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
