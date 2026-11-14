class_name SaveLoadDialog extends ModalWindow

# U10 (ATTN_17 §17.3.1): новый файл
## Сохранить или загрузить макет. Список файлов из user://saves/ (свежие сверху).
## В режиме «Сохранить» есть поле названия: файл называется по нему. Перезапись спрашивает через `confirm`.

## ⚡ Нажато «Сохранить» с названием макета
signal save_requested(layout_name: String)
## ⚡ Нажато «Загрузить» на файле (имя файла без .tres)
signal load_requested(slot: String)

enum Mode { SAVE, LOAD }

## Диалог подтверждения перезаписи, ставит SystemMenu
var confirm: ConfirmDialog

@onready var _name_row: HBoxContainer = %NameRow
@onready var _name_edit: LineEdit = %NameEdit
@onready var _list: ItemList = %SaveList
@onready var _empty: Label = %EmptyLabel
@onready var _ok: Button = %OkButton
@onready var _cancel: Button = %CancelButton

var _mode := Mode.LOAD
var _slots: Array[String] = []


func _ready() -> void:
	visible = false
	_ok.pressed.connect(_accept)
	_cancel.pressed.connect(close)
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(func(_i: int) -> void: _accept())
	_name_edit.text_submitted.connect(func(_t: String) -> void: _accept())
	_name_edit.text_changed.connect(func(_t: String) -> void: _update_ok())


func open_save(current_name: String) -> void:
	_mode = Mode.SAVE
	_name_row.visible = true
	_name_edit.text = current_name
	_ok.text = "Сохранить"
	_refresh()
	open("Сохранить макет")
	_name_edit.grab_focus()
	_name_edit.select_all()


func open_load() -> void:
	_mode = Mode.LOAD
	_name_row.visible = false
	_ok.text = "Загрузить"
	_refresh()
	open("Загрузить макет")


func _refresh() -> void:
	_list.clear()
	_slots.clear()
	var saves: Array[Dictionary] = (get_node("/root/GameRoot/SaveManager") as SaveManager).list_saves()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	for s in saves:
		_slots.append(s["slot"])
		var stamp := Time.get_datetime_string_from_unix_time(int(s["time"]) + bias, true)
		_list.add_item("%s    %s" % [s["slot"], stamp])
	_empty.visible = _slots.is_empty()
	_list.visible = not _slots.is_empty()
	_update_ok()


func _update_ok() -> void:
	if _mode == Mode.SAVE:
		_ok.disabled = _name_edit.text.strip_edges() == ""
	else:
		_ok.disabled = _list.get_selected_items().is_empty()


func _on_item_selected(index: int) -> void:
	if _mode == Mode.SAVE:
		_name_edit.text = _slots[index]   # выбрать файл = перезаписать его
	_update_ok()


func _accept() -> void:
	if _ok.disabled:
		return
	if _mode == Mode.LOAD:
		var sel := _list.get_selected_items()
		var slot := _slots[sel[0]]
		close()
		load_requested.emit(slot)
		return
	var layout := _name_edit.text.strip_edges()
	var slot := SaveManager.slot_from_name(layout)
	if _slots.has(slot) and confirm != null:
		if not await confirm.ask("Перезаписать?", "Файл «%s» уже есть. Заменить его?" % slot, "Заменить", "Отмена"):
			return
	close()
	save_requested.emit(layout)
