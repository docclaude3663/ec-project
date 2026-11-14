class_name TopBar extends PanelContainer

# U9 (ATTN_17 §17.4): новый файл, заменяет TopPanel и ModeLabel
########################
## Верхняя полоса HUD. Слева: системное меню и название макета. По центру: статистика макета (StatsBar).
## Справа: переключатели (временно, до SideDock в U12) и ModePanel с пятью кнопками режимов.
## Статистику считает LayoutStats, чипы описаны данными (StatSpec). Что не влезло, уходит в список «…».
########################

const CHIP_SCENE := preload("res://ui/widgets/stat_chip.tscn")
## Пути к сервисам игры: HUD → UI → GameRoot
@onready var save_manager: SaveManager = $"../../../SaveManager"
## Кнопка системного меню: пункты и действия задаёт SystemMenu (U10)
@onready var menu_button: MenuButton = %SystemMenu
## Чекбокс слоя питания (временно тут, потом SideDock)
@onready var power_schema_check: CheckBox = %PowerSchemaCheck
## Чекбокс теней от траков (временно тут, потом SideDock)
@onready var track_shadows_check: CheckBox = %TrackShadowsCheck

@onready var _stats_host: Control = %StatsHost
@onready var _stats_bar: HBoxContainer = %StatsBar
@onready var _more: MenuButton = %MoreStats
@onready var _lab_label: Label = %LabLabel
@onready var _layout_name: Label = %LayoutNameLabel
@onready var _layout_edit: LineEdit = %LayoutNameEdit

var _stats: LayoutStats
var _chips: Array[StatChip] = []


## Перечень чипов. Новый чип: одна строка (id, название для тултипа, подпись без иконки, поле LayoutStats,
## путь иконки, единица, знаков после запятой, скрывать ли ноль)
static func stat_specs() -> Array[StatSpec]:
	return [
		StatSpec.make(&"tracks", "Траки на столе", "Траки", &"tracks", "res://ui/icons/railroad/straight_wood_ballast.svg"),
		StatSpec.make(&"length", "Общая длина траков", "Длина", &"track_length", "", "u", 0),
		StatSpec.make(&"wagons", "Вагоны и локомотивы", "Вагоны", &"wagons"),
		StatSpec.make(&"consists", "Составы (сцепленные вагоны, от двух)", "Составы", &"consists"),
		StatSpec.make(&"contours", "Занятые контуры питания", "Контуры", &"contours", "res://ui/icons/electric/electric.svg"),
		StatSpec.make(&"others", "Прочие объекты", "Объекты", &"others"),
	]


func _ready() -> void:
	# Слой питания могут переключить не из чекбокса (Observe при входе/выходе): держим вид в синхроне
	PGM.power_layer_toggled.connect(_on_power_layer_toggled)
	power_schema_check.set_pressed_no_signal(PGM.is_power_layer_active)
	track_shadows_check.set_pressed_no_signal(GFX.is_track_shadows())
	GFX.track_shadows_changed.connect(_on_track_shadows_changed)
	# Название макета: показывает SaveManager.layout_name, двойной щелчок переименовывает
	save_manager.layout_name_changed.connect(_on_layout_name_changed)
	_on_layout_name_changed(save_manager.layout_name)
	_layout_name.gui_input.connect(_on_layout_name_gui_input)
	_layout_edit.text_submitted.connect(func(_t: String) -> void: _end_rename(true))
	_layout_edit.focus_exited.connect(func() -> void: _end_rename(true))
	_layout_edit.gui_input.connect(_on_layout_edit_gui_input)
	_build_style_selector()

	# Метка Lab: прежний «[LAB]» из ModeLabel
	GFX.lab_changed.connect(_on_lab_changed)
	_on_lab_changed(GFX.lab_mode)

	# Статистика
	for spec in stat_specs():
		var chip: StatChip = CHIP_SCENE.instantiate()
		_stats_bar.add_child(chip)
		_stats_bar.move_child(chip, _more.get_index())
		chip.setup(spec)
		_chips.append(chip)
	_stats = LayoutStats.new()
	_stats.name = &"LayoutStats"
	add_child(_stats)
	_stats.changed.connect(_refresh_stats)
	_stats_host.resized.connect(_fit_stats)
	_refresh_stats()


## Кнопка меню для SystemMenu
func get_system_menu_button() -> MenuButton:
	return menu_button


func _on_layout_name_changed(layout: String) -> void:
	_layout_name.text = layout


func _on_layout_name_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
		_layout_edit.text = _layout_name.text
		_layout_name.visible = false
		_layout_edit.visible = true
		_layout_edit.grab_focus()
		_layout_edit.select_all()


func _on_layout_edit_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_end_rename(false)
		_layout_edit.accept_event()


func _end_rename(apply: bool) -> void:
	if not _layout_edit.visible:
		return
	var txt := _layout_edit.text
	_layout_edit.visible = false
	_layout_name.visible = true
	if apply:
		save_manager.set_layout_name(txt)


## Кнопки режимов для ModeController (сам узел внутри этой сцены, снаружи по % не виден)
func get_mode_panel() -> Node:
	return %ModePanel


func _on_lab_changed(on: bool) -> void:
	_lab_label.visible = on


func _refresh_stats() -> void:
	for chip in _chips:
		chip.set_value(float(_stats.get(chip.spec.key)))
	_fit_stats()


## Чипы слева направо, пока помещаются; остальные скрыты и перечислены в «…».
## Нулевые (hide_zero) скрыты всегда. Размер StatsHost от содержимого не зависит
func _fit_stats() -> void:
	var avail := _stats_host.size.x
	var sep := float(_stats_bar.get_theme_constant(&"separation"))
	var wanted: Array[StatChip] = []
	for chip in _chips:
		if chip.has_value:
			wanted.append(chip)
		else:
			chip.visible = false
	var total := 0.0
	for chip in wanted:
		total += chip.get_combined_minimum_size().x + sep
	var limit := avail
	if total - sep > avail:
		limit = avail - _more.get_combined_minimum_size().x - sep
	var used := 0.0
	var overflow: Array[String] = []
	for chip in wanted:
		var w := chip.get_combined_minimum_size().x
		if used + w <= limit:
			chip.visible = true
			used += w + sep
		else:
			chip.visible = false
			overflow.append(chip.summary())
	_more.visible = not overflow.is_empty()
	var more_popup := _more.get_popup()
	more_popup.clear()
	for line in overflow:
		more_popup.add_item(line)
		more_popup.set_item_disabled(more_popup.item_count - 1, true)


## Временный выбор стиля траков сессии (ATTN_17 §17.13, U3c). Место в ToolDock решается в U7a.
## Список строится из набора стилей проекта (TSM), собирается кодом, чтобы не трогать сцену
var _style_option: OptionButton
var _style_apply_button: Button
var _style_apply_dialog: ConfirmationDialog


func _build_style_selector() -> void:
	_style_option = OptionButton.new()
	_style_option.focus_mode = Control.FOCUS_NONE   # стрелки и пробел остаются инструментам
	_style_option.tooltip_text = "Стиль траков: новые траки создаются в нём, стоящие не меняются"
	_fill_style_items()
	_style_option.item_selected.connect(_on_style_selected)
	TSM.current_changed.connect(_sync_style_selector)
	TSM.set_changed.connect(_fill_style_items)   # Track Studio добавил стиль в набор
	var box := power_schema_check.get_parent()
	box.add_child(_style_option)
	box.move_child(_style_option, power_schema_check.get_index())
	# Этап 3: применить стиль сессии ко всем тракам на столе (с подтверждением)
	_style_apply_button = Button.new()
	_style_apply_button.text = "Ко всем"
	_style_apply_button.focus_mode = Control.FOCUS_NONE
	_style_apply_button.tooltip_text = "Пересобрать все траки на столе в выбранном стиле. Макет сохраняется в автосейв."
	_style_apply_button.pressed.connect(_on_style_apply_pressed)
	box.add_child(_style_apply_button)
	box.move_child(_style_apply_button, _style_option.get_index() + 1)
	_style_apply_dialog = ConfirmationDialog.new()
	_style_apply_dialog.title = "Стиль всех траков"
	_style_apply_dialog.ok_button_text = "Применить"
	_style_apply_dialog.cancel_button_text = "Отмена"
	_style_apply_dialog.confirmed.connect(_on_style_apply_confirmed)
	add_child(_style_apply_dialog)


## Строки списка из набора стилей проекта; пересобирается, когда набор изменился
func _fill_style_items() -> void:
	_style_option.clear()
	for st in TSM.style_set.styles:
		if st == null:
			continue
		var i := _style_option.item_count
		_style_option.add_item(String(st.id))
		_style_option.set_item_metadata(i, st.id)
		var tip := "высота рельса %.2f" % st.head_height()
		if st.use_scene:
			tip += ", сцены Blender"
		_style_option.set_item_tooltip(i, tip)
	_sync_style_selector(TSM.current_id)


func _on_style_apply_pressed() -> void:
	_style_apply_dialog.dialog_text = "Все траки на столе будут пересобраны в стиле «%s».\nМакет перед этим сохраняется в автосейв: до следующего сохранения им можно откатиться (загрузить autosave).\nПродолжить?" % TSM.current_id
	_style_apply_dialog.popup_centered()


func _on_style_apply_confirmed() -> void:
	_style_apply_button.disabled = true
	await save_manager.apply_session_style_to_all()
	_style_apply_button.disabled = false


func _on_style_selected(index: int) -> void:
	TSM.set_current(_style_option.get_item_metadata(index))


## Список показывает активный стиль, в том числе после загрузки сейва
func _sync_style_selector(id: StringName) -> void:
	for i in _style_option.item_count:
		if _style_option.get_item_metadata(i) == id:
			_style_option.select(i)
			return


## Включение Cлоя power (11) на камере. Режим повер 2лвл
func _on_power_schema_check_toggled(toggled_on: bool) -> void:
	#$/root/GameRoot/Gimbal/Elevation/Camera.set_cull_mask_value(3, toggled_on)	

	# Дергаем менеджер питания
	PGM.toggle_power_layer(toggled_on)


## ⚡Сигнал из PGM: слой питания переключён. Двигаем чекбокс без повторного сигнала
func _on_power_layer_toggled(is_active: bool) -> void:
	power_schema_check.set_pressed_no_signal(is_active)


## Тени от траков вкл/выкл. Выбор сохраняется в settings.cfg
func _on_track_shadows_check_toggled(toggled_on: bool) -> void:
	GFX.set_track_shadows(toggled_on)


## ⚡Сигнал из GFX: настройка или tier поменялись извне. Двигаем чекбокс без повторного сигнала
func _on_track_shadows_changed(on: bool) -> void:
	track_shadows_check.set_pressed_no_signal(on)
