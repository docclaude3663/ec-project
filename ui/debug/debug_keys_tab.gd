class_name DebugKeysTab extends DebugTab

###########################
## Вкладка «Keys»: отладочные клавиши (U14, U6.2)
###########################
## Справочник клавиш, которые работают при Global.debug_mode. Список и описания в DebugKeys, клавиши из реестра Actions:
## после переназначения здесь видна новая. Кнопка «Нажать» шлёт в игру действие, а не клавишу (удобно, когда F-клавиши
## заняты системой). F7 кнопки не имеет: ему нужен курсор над макетом.


func _init() -> void:
	name = &"Keys"
	add_child(make_note("Работают при Global.debug_mode (в редакторе и debug-сборке)."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 8)
	add_child(grid)
	for k in DebugKeys.LIST:
		var key := Label.new()
		key.text = DebugKeys.key_label(k)
		key.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key)
		var text := make_note(k.text)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(text)
		if k.press:
			var send := Button.new()
			send.text = "Нажать"
			var action: StringName = k.action
			send.pressed.connect(func() -> void: _press_action(action))
			grid.add_child(send)
		else:
			grid.add_child(Control.new())


## Шлет действие InputMap (нажатие и отпускание)
func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
