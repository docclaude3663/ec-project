class_name DebugPanel extends PanelContainer

###########################
## DebugPanel. Отладка и настройка вагонов (U14)
###########################
## Создается GameRoot только при Global.debug_mode (в релизе узла нет). Открывается клавишей F3
## (действие debug_panel_toggle), закрывается ей же или крестиком, тянется за заголовок, размер меняется ручкой в правом нижнем углу.
## Колесо мыши над панелью не доходит до камеры, даже когда вкладка доскроллена до края.
## Вкладки: Tuning, Suspension и Layout (параметры выбранного вагона), Graphics (правка Look, Time, Quality на лету), Lab (корректор графики на чистом дефолте Godot), Entity (компоненты), Perf (fps, отрисовка, физика),
## Toggles (флаги Global), Keys (отладочные клавиши). Вкладки лежат в ui/debug/debug_*_tab.gd.
## Выбранный объект приходит сигналом ToolController.selection_changed. Положение и размер окна пишутся в Settings [debug] (panel_pos, panel_size).
## Когда появится FloatingPanel (U13), перетаскивание и положение переедут в него.

const ACTION := &"debug_panel_toggle"
const SETTINGS_SECTION := "debug"
const POS_KEY := "panel_pos"
const SIZE_KEY := "panel_size"
const VARS_KEY := "show_vars"
## Частота обновления живых значений открытой вкладки, раз в секунду
const REFRESH_HZ := 10.0
const DEFAULT_POS := Vector2(16.0, 56.0)
const PANEL_WIDTH := 460.0
## Размер окна по умолчанию и наименьший размер, до которого его можно сжать
const DEFAULT_SIZE := Vector2(460.0, 560.0)
const MIN_SIZE := Vector2(320.0, 240.0)

var _tool_controller: ToolController
var _tabs: TabContainer
## Вкладки по их оболочке в TabContainer (ScrollContainer): оболочка -> DebugTab
var _tab_by_scroll: Dictionary = {}
var _target: Entity
var _vars_check: CheckBox
var _acc := 0.0
var _dragging := false
var _drag_offset := Vector2.ZERO
var _resizing := false
## Расстояние от курсора до правого нижнего угла окна в момент нажатия на ручку
var _resize_grab := Vector2.ZERO
var _panel_size := DEFAULT_SIZE


## Ручка размера окна: треугольник в правом нижнем углу
class _Grip extends Control:
	func _draw() -> void:
		var r := size
		draw_colored_polygon(PackedVector2Array([Vector2(r.x, 2.0), Vector2(r.x, r.y), Vector2(2.0, r.y)]), Color(1.0, 1.0, 1.0, 0.45))


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP   # клик по панели не доходит до мира

	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(_make_header())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(_tabs)
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_TUNING))
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_SUSPENSION))
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_LAYOUT))
	_add_tab(DebugGraphicsTab.new())
	_add_tab(DebugLabTab.new())
	_add_tab(DebugEntityTab.new())
	_add_tab(DebugPerfTab.new())
	_add_tab(DebugTogglesTab.new())
	_add_tab(DebugKeysTab.new())
	root.add_child(_make_footer())

	_set_show_vars(bool(Settings.get_value(SETTINGS_SECTION, VARS_KEY, false)))
	position = Settings.get_value(SETTINGS_SECTION, POS_KEY, DEFAULT_POS)
	var saved_size: Variant = Settings.get_value(SETTINGS_SECTION, SIZE_KEY, DEFAULT_SIZE)
	_panel_size = _clamp_size(saved_size if saved_size is Vector2 else DEFAULT_SIZE)
	_apply_size()
	get_viewport().size_changed.connect(_clamp_to_screen)
	_clamp_to_screen.call_deferred()


## Зовет GameRoot сразу после создания: связывает панель с игрой. Панель сама не ищет узлы по путям
func setup(tool_controller: ToolController, save_manager: SaveManager) -> void:
	_tool_controller = tool_controller
	_target = tool_controller.current_target
	tool_controller.selection_changed.connect(_on_selection_changed)
	for tab in _tab_by_scroll.values():
		if tab is DebugEntityTab:
			(tab as DebugEntityTab).setup(tool_controller)
		elif tab is DebugTogglesTab:
			(tab as DebugTogglesTab).setup(save_manager)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and _is_wheel(event) and get_global_rect().has_point(get_global_mouse_position()):
		get_viewport().set_input_as_handled()   # страховка: колесо над панелью не зумит камеру


## Колесо над панелью. ScrollContainer на краю прокрутки отдает событие выше, и без этого оно доходило бы до зума камеры
func _gui_input(event: InputEvent) -> void:
	if _is_wheel(event):
		accept_event()


static func _is_wheel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var b := (event as InputEventMouseButton).button_index
	return b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN \
			or b == MOUSE_BUTTON_WHEEL_LEFT or b == MOUSE_BUTTON_WHEEL_RIGHT


func toggle() -> void:
	visible = not visible
	if visible:
		_bind_tabs()
		_clamp_to_screen()
	else:
		for tab in _tab_by_scroll.values():
			(tab as DebugTab).closed()


func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	if _acc < 1.0 / REFRESH_HZ:
		return
	_acc = 0.0
	var tab := _active_tab()
	if tab:
		tab.refresh()


func _add_tab(tab: DebugTab) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab.name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(MIN_SIZE.x - 20.0, 120.0)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tab)
	_tabs.add_child(scroll)
	_tab_by_scroll[scroll] = tab


func _active_tab() -> DebugTab:
	return _tab_by_scroll.get(_tabs.get_current_tab_control())


func _on_tab_changed(_idx: int) -> void:
	var tab := _active_tab()
	if tab:
		tab.opened()


func _on_selection_changed(entity: Entity) -> void:
	_target = entity
	# Закрытая панель не работает; при открытии привяжется к _target
	if visible:
		_bind_tabs()


func _bind_tabs() -> void:
	var valid := _target if is_instance_valid(_target) else null
	for tab in _tab_by_scroll.values():
		(tab as DebugTab).bind(valid)
	var active := _active_tab()
	if active:
		active.opened()


# --- заголовок и перетаскивание ---

func _make_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_header_input)
	var title := Label.new()
	title.text = "Debug (F3)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_vars_check = CheckBox.new()
	_vars_check.text = "Переменные"
	_vars_check.tooltip_text = "Показать имена переменных мелким шрифтом под названием параметра"
	_vars_check.focus_mode = Control.FOCUS_NONE
	_vars_check.toggled.connect(_on_vars_toggled)
	header.add_child(_vars_check)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	header.add_child(close)
	return header


## Нижняя полоса с ручкой размера окна
func _make_footer() -> Control:
	var footer := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	var grip := _Grip.new()
	grip.custom_minimum_size = Vector2(20.0, 20.0)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Потянуть: размер окна"
	grip.gui_input.connect(_on_grip_input)
	footer.add_child(grip)
	return footer


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if _resizing:
			_resize_grab = global_position + size - get_global_mouse_position()
		else:
			Settings.set_value(SETTINGS_SECTION, SIZE_KEY, _panel_size)
	elif event is InputEventMouseMotion and _resizing:
		_panel_size = _clamp_size(get_global_mouse_position() + _resize_grab - global_position)
		_apply_size()


## Размер не меньше MIN_SIZE и не выходит за экран от текущего положения окна
func _clamp_size(v: Vector2) -> Vector2:
	var room := get_viewport_rect().size - position
	return Vector2(clampf(v.x, MIN_SIZE.x, maxf(MIN_SIZE.x, room.x)), clampf(v.y, MIN_SIZE.y, maxf(MIN_SIZE.y, room.y)))


func _apply_size() -> void:
	custom_minimum_size = _panel_size
	size = _panel_size


func _on_vars_toggled(on: bool) -> void:
	_set_show_vars(on)
	Settings.set_value(SETTINGS_SECTION, VARS_KEY, on)


## Показ имен переменных на всех вкладках и состояние кнопки в заголовке
func _set_show_vars(on: bool) -> void:
	_vars_check.set_pressed_no_signal(on)
	for tab in _tab_by_scroll.values():
		(tab as DebugTab).set_show_vars(on)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - global_position
		else:
			_clamp_to_screen()
			Settings.set_value(SETTINGS_SECTION, POS_KEY, position)
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset


## Не дает окну уйти за экран (заголовок остается доступен)
func _clamp_to_screen() -> void:
	var screen := get_viewport_rect().size
	if _clamp_size(_panel_size) != _panel_size:
		_panel_size = _clamp_size(_panel_size)
		_apply_size()
	var max_pos := (screen - size).max(Vector2.ZERO)
	position = position.clamp(Vector2.ZERO, max_pos)
