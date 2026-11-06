class_name DebugPanel extends PanelContainer

###########################
## DebugPanel. Отладка и настройка вагонов (U14)
###########################
## Создается GameRoot только при Global.debug_mode (в релизе узла нет). Открывается клавишей F3
## (действие debug_panel_toggle), закрывается ей же или крестиком, тянется за заголовок.
## Вкладки: Tuning, Suspension и Layout (параметры выбранного вагона), Graphics (правка Look, Time, Quality на лету), Entity (компоненты), Perf (fps, отрисовка, физика),
## Toggles (флаги Global), Keys (отладочные клавиши). Вкладки лежат в ui/debug/debug_*_tab.gd.
## Выбранный объект приходит сигналом ToolController.selection_changed. Положение окна пишется в Settings [debug].
## Когда появится FloatingPanel (U13), перетаскивание и положение переедут в него.

const ACTION := &"debug_panel_toggle"
const SETTINGS_SECTION := "debug"
const POS_KEY := "panel_pos"
const VARS_KEY := "show_vars"
## Частота обновления живых значений открытой вкладки, раз в секунду
const REFRESH_HZ := 10.0
const DEFAULT_POS := Vector2(16.0, 56.0)
const PANEL_WIDTH := 460.0
const TABS_HEIGHT := 460.0

var _tool_controller: ToolController
var _tabs: TabContainer
## Вкладки по их оболочке в TabContainer (ScrollContainer): оболочка -> DebugTab
var _tab_by_scroll: Dictionary = {}
var _target: Entity
var _vars_check: CheckBox
var _acc := 0.0
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	hide()
	_ensure_action()
	mouse_filter = Control.MOUSE_FILTER_STOP   # клик по панели не доходит до мира
	custom_minimum_size.x = PANEL_WIDTH

	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(_make_header())

	_tabs = TabContainer.new()
	_tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(_tabs)
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_TUNING))
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_SUSPENSION))
	_add_tab(DebugTuningTab.new(WagonTuning.TAB_LAYOUT))
	_add_tab(DebugGraphicsTab.new())
	_add_tab(DebugEntityTab.new())
	_add_tab(DebugPerfTab.new())
	_add_tab(DebugTogglesTab.new())
	_add_tab(DebugKeysTab.new())

	_set_show_vars(bool(Settings.get_value(SETTINGS_SECTION, VARS_KEY, false)))
	position = Settings.get_value(SETTINGS_SECTION, POS_KEY, DEFAULT_POS)
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


## Если действия нет в InputMap (проект открыт без записи в project.godot), заводим F3 сами
func _ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	InputMap.action_add_event(ACTION, ev)


func _add_tab(tab: DebugTab) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab.name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 20.0, TABS_HEIGHT)
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
	var max_pos := (screen - size).max(Vector2.ZERO)
	position = position.clamp(Vector2.ZERO, max_pos)
