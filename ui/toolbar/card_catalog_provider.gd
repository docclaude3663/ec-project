class_name CardCatalogProvider extends CatalogProvider

###########################
## CardCatalogProvider. Карточки режима Observe (пресеты, время суток, камеры, комната, фото)
###########################
## Вместо отрисовки в ObserveController. Данные карточек (CARDS) и состояние радио-групп и переключателей
## живут здесь: состояние переживает пересборку категории (кнопки создаются заново при каждом показе).
## Нажатие карточки уходит приемнику режима: on_pressed.call(category, id, pressed).
## Тегов у Observe нет, кнопки категории строятся сразу.
## TODO S3: источник правды станет GraphicsManager.state

## Категории (нижний ряд). TODO иконки
const CATEGORIES := [
	{"id": &"look", "name": "Look", "icon": null},
	{"id": &"light", "name": "Light", "icon": null},
	{"id": &"camera", "name": "Camera", "icon": null},
	{"id": &"room", "name": "Room", "icon": null},
	{"id": &"photo", "name": "Photo", "icon": null},
	{"id": &"weather", "name": "Weather", "icon": null},
]

## Карточки по категориям. group: радио-группа, toggle: переключатель, без них: разовое действие.
## Большинство пока заглушки, рабочими их делают шаги S3-S9.
const CARDS := {
	&"look": [
		{"id": &"toy", "title": "Toy", "group": &"look", "default": true},
		{"id": &"workshop", "title": "Workshop", "group": &"look"},
		{"id": &"clean", "title": "Clean", "group": &"look"},
		{"id": &"low", "title": "Low", "group": &"quality"},
		{"id": &"medium", "title": "Medium", "group": &"quality", "default": true},
		{"id": &"high", "title": "High", "group": &"quality"},
		# Только debug (см. _cards_for): чистый дефолт Godot для корректора графики (GfxLab, ATTN_14 §14.16)
		{"id": &"lab_default", "title": "Default", "tip": "Сброс всего к дефолту Godot: Look, Time, Quality, свет, камера (без позиции и зума). Дальше правки в Remote или во вкладке Lab (F3). Любая другая карточка Look, Time или Quality возвращает игру"},
	],
	&"light": [
		{"id": &"morning", "title": "Утро", "group": &"time"},
		{"id": &"day", "title": "День", "group": &"time", "default": true},
		{"id": &"evening", "title": "Вечер", "group": &"time"},
		{"id": &"night", "title": "Ночь", "group": &"time"},
		{"id": &"lamp", "title": "Лампа", "toggle": true},
	],
	&"camera": [
		{"id": &"bookmark_1", "title": "1", "tip": "Закладка 1: перейти, пустая: сохранить. Shift: перезаписать (клавиши 1-5, Ctrl+1-5)"},
		{"id": &"bookmark_2", "title": "2", "tip": "Закладка 2: перейти, пустая: сохранить. Shift: перезаписать"},
		{"id": &"bookmark_3", "title": "3", "tip": "Закладка 3: перейти, пустая: сохранить. Shift: перезаписать"},
		{"id": &"bookmark_4", "title": "4", "tip": "Закладка 4: перейти, пустая: сохранить. Shift: перезаписать"},
		{"id": &"bookmark_5", "title": "5", "tip": "Закладка 5: перейти, пустая: сохранить. Shift: перезаписать"},
		{"id": &"follow", "title": "Follow", "toggle": true, "tip": "Камера вагона. Сначала кликните по вагону. Esc: выйти"},
		{"id": &"pov", "title": "POV", "toggle": true, "tip": "Вид из вагона. Сначала кликните по вагону. Esc: выйти"},
		{"id": &"pov_flip", "title": "POV ↔", "toggle": true, "tip": "Развернуть POV-камеру в другую сторону"},
		{"id": &"orbit", "title": "Orbit", "toggle": true, "tip": "Автокамера вокруг стола. Esc: выйти"},
	],
	&"room": [
		{"id": &"room_visible", "title": "Комната", "toggle": true, "default": true},
		{"id": &"ceiling", "title": "Потолок", "toggle": true},
		# Здесь стоят карточки выбора комнаты (группа room_pick): их строит _cards_for из RoomCatalog (встроенные и папки data/rooms)
		{"id": &"wall_cream", "title": "Стены: беж", "group": &"wall"},
		{"id": &"wall_sky", "title": "Стены: небо", "group": &"wall"},
		{"id": &"wall_mint", "title": "Стены: мята", "group": &"wall"},
		{"id": &"wall_blue", "title": "Стены: синий", "group": &"wall"},
		{"id": &"wall_dusty", "title": "Стены: пыльный голубой", "group": &"wall", "default": true},
		{"id": &"wall_slate", "title": "Стены: сланец", "group": &"wall"},
		{"id": &"wall_sage", "title": "Стены: шалфей", "group": &"wall"},
		{"id": &"bed_blue", "title": "Постель: синяя", "group": &"bedding", "default": true},
		{"id": &"bed_red", "title": "Постель: красная", "group": &"bedding"},
		{"id": &"bed_green", "title": "Постель: зелёная", "group": &"bedding"},
		{"id": &"curt_yellow", "title": "Шторы: жёлтые", "group": &"curtains", "default": true},
		{"id": &"curt_red", "title": "Шторы: красные", "group": &"curtains"},
		{"id": &"curt_blue", "title": "Шторы: синие", "group": &"curtains"},
		{"id": &"poster_trains", "title": "Постеры: поезда", "group": &"posters", "default": true},
		{"id": &"poster_map", "title": "Постеры: карта", "group": &"posters"},
		{"id": &"poster_space", "title": "Постеры: космос", "group": &"posters"},
	],
	&"photo": [
		{"id": &"hide_ui", "title": "Скрыть UI", "toggle": true, "tip": "Клавиша H. Esc: вернуть UI"},
		{"id": &"snapshot", "title": "Снять", "tip": "Клавиша P. Снимок без UI на качестве High: user://screenshots/"},
	],
	&"weather": [
		{"id": &"soon", "title": "Weather", "locked": true},
	],
}

var _groups := {}         # имя группы -> ButtonGroup (пересоздаются при каждом показе категории)
var _group_state := {}    # группа -> id выбранной карточки
var _toggle_state := {}   # id -> bool
var _cards: Array = []    # созданные сейчас карточки (могут быть уже освобождены, см. is_instance_valid)


## В режиме быстрой загрузки (--fast) Observe недоступен: категорий нет
func get_categories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Global.fast_debug:
		return out
	for c in CATEGORIES:
		out.append(c)
	return out


func create_buttons(category: StringName, _tag: StringName, on_pressed: Callable, _filters: Dictionary = {}) -> Array[Button]:
	var out: Array[Button] = []
	_groups.clear()
	_cards.clear()
	for data in _cards_for(category):
		var card := ObserveCard.new()
		card.config(category, data, _group_for(data))
		if card.toggle_mode:
			card.set_pressed_no_signal(_is_on(data))
		card.card_pressed.connect(_on_card_pressed.bind(on_pressed))
		_cards.append(card)
		out.append(card)
	return out


func _group_for(data: Dictionary) -> ButtonGroup:
	var g: StringName = data.get("group", &"")
	if g == &"":
		return null
	if not _groups.has(g):
		_groups[g] = ButtonGroup.new()
	return _groups[g]


## ⚡Сигнал из карточки: запоминаем состояние и отдаем приемнику
func _on_card_pressed(category: StringName, id: StringName, pressed: bool, on_pressed: Callable) -> void:
	var data := _card_data(category, id)
	var g: StringName = data.get("group", &"")
	if g != &"":
		if pressed:
			_group_state[g] = id
	elif data.get("toggle", false):
		_toggle_state[id] = pressed
	if on_pressed.is_valid():
		on_pressed.call(category, id, pressed)


## Программная смена выбранной карточки группы (GFX при смене Look/Time из кода). Сигнал карточки не шлется
func set_group_state(group: StringName, id: StringName) -> void:
	_group_state[group] = id
	var g: ButtonGroup = _groups.get(group)
	if g == null:
		return
	for b in g.get_buttons():
		if b is ObserveCard:
			b.set_pressed_no_signal(b.id == id)


## То же для переключателя
func set_toggle_state(id: StringName, on: bool) -> void:
	_toggle_state[id] = on
	for c in _cards:
		if is_instance_valid(c) and c.id == id and c.toggle_mode:
			c.set_pressed_no_signal(on)


## Нажата ли карточка при показе: из сохраненного состояния, иначе по "default"
func _is_on(data: Dictionary) -> bool:
	var g: StringName = data.get("group", &"")
	if g == &"room_pick":
		# Живая комната: её могла сменить загрузка сейва
		var tree := Engine.get_main_loop() as SceneTree
		var rb := tree.get_first_node_in_group(&"room_root") as RoomBuilder if tree else null
		if rb != null:
			return &"room_" + String(rb.get_room_id()) == String(data.id)
	if g != &"":
		if _group_state.has(g):
			return _group_state[g] == data.id
		return data.get("default", false)
	if data.get("toggle", false):
		return _toggle_state.get(data.id, data.get("default", false))
	return false


## Карточки категории. В Room после «Потолок» вставляются комнаты из RoomCatalog (радио-группа room_pick), а в редакторе
## ещё и кнопка записи комнаты в сцену
func _cards_for(category: StringName) -> Array:
	var base: Array = CARDS.get(category, [])
	if category == &"look" and not Global.debug_mode:
		return base.filter(func(d: Dictionary) -> bool: return d.id != &"lab_default")
	if category != &"room":
		return base
	var out: Array = []
	for d in base:
		out.append(d)
		if d.id == &"ceiling":
			for e in RoomCatalog.entries():
				out.append({"id": StringName("room_" + String(e.id)), "title": "Комната: " + String(e.title).to_lower(),
						"group": &"room_pick", "default": e.id == RoomCatalog.DEFAULT_ID, "tip": e.tip})
			if OS.has_feature("editor"):
				out.append({"id": &"room_save_scene", "title": "Комнату в сцену",
						"tip": "Только из редактора. Записывает текущую процедурную комнату в data/rooms/<id>/ (сцена и паспорт). Со следующего запуска комната берётся из сцены"})
	return out


func _card_data(category: StringName, id: StringName) -> Dictionary:
	for d in _cards_for(category):
		if d.id == id:
			return d
	return {}
