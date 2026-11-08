class_name ConsistButtonMenu extends RefCounted

###########################
## ConsistButtonMenu. Правая кнопка на кнопке состава игрока: переименовать, удалить
###########################
## Меню и диалоги создаются на лету и живут дочерними узлами кнопки: пересборка сетки каталога
## удаляет кнопку вместе с ними. Встроенные шаблоны автора (res://) меню не получают.

const ID_RENAME := 0
const ID_DELETE := 1


## Вешает на кнопку меню по ПКМ. on_changed зовётся после успешного переименования или удаления
static func attach(btn: ObjectButton, setting: ConsistSetting, on_changed: Callable) -> void:
	btn.tooltip_text += "\n(Правая кнопка: переименовать, удалить)"
	btn.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			btn.accept_event()   # ПКМ в Build снимает выбор объекта, здесь это не нужно
			_open_menu(btn, setting, on_changed)
	)


static func _open_menu(btn: ObjectButton, setting: ConsistSetting, on_changed: Callable) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Переименовать", ID_RENAME)
	menu.add_item("Удалить", ID_DELETE)
	menu.id_pressed.connect(func(id: int) -> void:
		match id:
			ID_RENAME:
				_ask_rename(btn, setting, on_changed)
			ID_DELETE:
				_ask_delete(btn, setting, on_changed)
		menu.queue_free()
	)
	menu.close_requested.connect(menu.queue_free)
	btn.add_child(menu)
	menu.popup(Rect2i(Vector2i(btn.get_screen_position() + btn.get_local_mouse_position()), Vector2i.ZERO))


static func _ask_rename(btn: ObjectButton, setting: ConsistSetting, on_changed: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Переименовать состав"
	var edit := LineEdit.new()
	edit.text = setting.template.name
	edit.custom_minimum_size.x = 320
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.confirmed.connect(func() -> void:
		var why := ConsistStore.rename(setting.template, edit.text)
		if why != "":
			push_warning("Consist: " + why)
			dlg.queue_free()
			return
		on_changed.call()
	)
	dlg.canceled.connect(dlg.queue_free)
	btn.add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus()
	edit.select_all()


static func _ask_delete(btn: ObjectButton, setting: ConsistSetting, on_changed: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Удалить состав"
	dlg.dialog_text = "Удалить состав «%s»? Вагоны на макете останутся, файл шаблона будет удалён." % setting.template.name
	dlg.ok_button_text = "Удалить"
	dlg.confirmed.connect(func() -> void:
		var why := ConsistStore.delete(setting.template)
		if why != "":
			push_warning("Consist: " + why)
			dlg.queue_free()
			return
		on_changed.call()
	)
	dlg.canceled.connect(dlg.queue_free)
	btn.add_child(dlg)
	dlg.popup_centered()
