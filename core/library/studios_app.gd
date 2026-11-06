extends Control

# XX claude-library (новый файл)
########################
## Приложение студий: Track Studio и Icon Studio отдельно от игры (ATTN_22 §22.5.1, шаг L1b)
########################
## Инструменты автора. Запуск: F6 на studios_app.tscn или `godot --path . res://core/library/studios_app.tscn`.
## Сверху выбор инструмента, под ним выбранная студия; по умолчанию Track Studio. Сами студии не меняются:
## каждая держит свой файл настроек и при запуске восстанавливает свой размер окна, поэтому при переключении
## окно может менять размер. Прежняя студия убирается из дерева сразу (её _exit_tree записывает настройки),
## а не в конце кадра: иначе она записала бы в свой файл размер окна уже новой студии.

const TOOLS := [
	{"id": &"track", "title": "Track Studio", "scene": "res://core/library/track_studio/track_studio.tscn"},
	{"id": &"icon", "title": "Icon Studio", "scene": "res://core/library/icon_studio/icon_studio.tscn"},
]
const DEFAULT_TOOL := &"track"

var _holder: Control
var _buttons := {}
var _current: Node
var _current_id: StringName = &""


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# set_anchors_preset без offsets оставляет прежний (нулевой) размер, поэтому именно _and_offsets_
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	var label := Label.new()
	label.text = "Студия:"
	bar.add_child(label)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t["title"]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_open.bind(t["id"]))
		bar.add_child(b)
		_buttons[t["id"]] = b

	_holder = Control.new()
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_holder)

	_open(DEFAULT_TOOL)


func _open(id: StringName) -> void:
	if id == _current_id:
		return
	var path := ""
	for t in TOOLS:
		if t["id"] == id:
			path = t["scene"]
	if path == "":
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Studios: не удалось загрузить %s" % path)
		return
	_set_buttons_disabled(true)
	if _current != null:
		_holder.remove_child(_current)
		_current.queue_free()
	_current_id = id
	(_buttons[id] as Button).set_pressed_no_signal(true)
	_current = packed.instantiate()
	_holder.add_child(_current)
	# Студия досоздаёт часть интерфейса после первого кадра: до этого переключать нельзя
	await get_tree().process_frame
	await get_tree().process_frame
	_set_buttons_disabled(false)


func _set_buttons_disabled(on: bool) -> void:
	for id in _buttons:
		(_buttons[id] as Button).disabled = on
