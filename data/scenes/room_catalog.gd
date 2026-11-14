class_name RoomCatalog extends RefCounted

########################
## Каталог комнат: id -> паспорт (RoomConfig). Комната в памяти одна (RoomBuilder.switch_room пересобирает её).
########################
## Два источника:
##  1. Карточка data/rooms/cards/<id>.tres (RoomConfig, id равен имени файла) со сценой в RoomConfig.scene (корень RoomRoot,
##     обычно data/rooms/<id>/<id>.tscn). Карточки читаются из одной папки, без вложенных (как data/<категория>/objects/ у объектов).
##     Новая комната из сцены = новая карточка в cards/, кода менять не нужно. Карточка без сцены каталогом не читается.
##  2. BUILTIN: процедурные комнаты, которые строит RoomBuilder кодом (ветки в make()). Если в cards/ лежит карточка
##     с тем же id, вместо процедурной берётся сцена. Сцену из процедурной комнаты записывает кнопка «Комнату в сцену» (F3 → Toggles, только редактор).
## Комнаты dev_only (стенд, куб) игроку не показываются: entries(true) их пропускает. Проверка папки: validate().

const DEFAULT_ID := &"kid_room_10"
const ROOMS_DIR := "res://data/rooms"
const CARDS_DIR := "res://data/rooms/cards"

## Процедурные комнаты: id, название и подсказка карточки. dev_only: тестовая, игроку не показывается
const BUILTIN := [
	{"id": &"kid_room_10", "title": "Детская", "tip": "Заменяет комнату целиком (в памяти одна)"},
	{"id": &"cube", "title": "Пустой куб", "tip": "Пустая коробка для текстур и импорта. Заменяет комнату целиком", "dev_only": true},
	{"id": &"bench", "title": "Стенд (только стол)", "tip": "Тестовая: только стол 1x2 м, без пола, стен и потолка. Включает оверлей статистики. Заменяет комнату целиком", "dev_only": true},
	{"id": &"attic", "title": "Мансарда", "tip": "Скос крыши, окна закрыты, свет только лампы дневного света. Заменяет комнату целиком"},
]


## Все комнаты для списков: [{id, title, tip, dev_only}]. Сначала встроенные (в своём порядке), затем остальные карточки по алфавиту.
## for_player: без комнат dev_only (список игрока при выборе комнаты в начале игры)
static func entries(for_player := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BUILTIN:
		var d: Dictionary = b.duplicate()
		d["dev_only"] = bool(d.get("dev_only", false))
		var c := _load_passport(b.id)
		if c:
			if c.title != "":
				d.title = c.title
			if c.tip != "":
				d.tip = c.tip
			d["dev_only"] = c.dev_only
		out.append(d)
	for path in _card_paths():
		var id := StringName(path.get_file().get_basename())
		if _is_builtin(id):
			continue
		var c := _load_passport(id)
		if c == null:
			continue
		out.append({"id": id, "title": c.title if c.title != "" else String(id), "tip": c.tip, "dev_only": c.dev_only})
	if for_player:
		out = out.filter(func(d: Dictionary) -> bool: return not d.dev_only)
	return out


## true: комната тестовая (игроку не показывается). Неизвестный id: false
static func is_dev_only(id: StringName) -> bool:
	for e in entries():
		if e.id == id:
			return e.dev_only
	return false


static func has(id: StringName) -> bool:
	if _is_builtin(id):
		return true
	return ResourceLoader.exists(_passport_path(id))


static func _is_builtin(id: StringName) -> bool:
	for b in BUILTIN:
		if b.id == id:
			return true
	return false


static func _passport_path(id: StringName) -> String:
	return "%s/%s.tres" % [CARDS_DIR, id]


## Пути карточек data/rooms/cards/*.tres (без вложенных папок), по алфавиту. В экспорте файлы могут стоять как .tres.remap
static func _card_paths(cards_dir := CARDS_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	var base := cards_dir + "/"
	var names := ResourceLoader.list_directory(base)
	if names.is_empty():
		names = DirAccess.get_files_at(base)
	for n in names:
		if n.ends_with(".tres"):
			out.append(base + n)
		elif n.ends_with(".tres.remap"):
			out.append(base + n.trim_suffix(".remap"))
	out.sort()
	return out


## Карточка из cards/ (общий ресурс, не менять). null: файла нет или в нём нет сцены
static func _load_passport(id: StringName) -> RoomConfig:
	var path := _passport_path(id)
	if not ResourceLoader.exists(path):
		return null
	var c := load(path) as RoomConfig
	if c == null or c.scene == null:
		return null
	return c


## Проверка папки комнат: список проблем (пусто: всё в порядке). Зовут tests/room_catalog_test.tscn и tests/catalog_lint.gd.
## cards_dir другой (только тест на плохих карточках): проверки старого места и комнаты по умолчанию пропускаются
static func validate(cards_dir := CARDS_DIR) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for path in _card_paths(cards_dir):
		var file_id := path.get_file().get_basename()
		var c := load(path) as RoomConfig
		if c == null:
			out.append("%s: это не RoomConfig" % path)
			continue
		if String(c.id) != file_id:
			out.append("%s: id '%s' не равен имени файла" % [path, c.id])
		if seen.has(c.id):
			out.append("%s: id '%s' уже у %s" % [path, c.id, seen[c.id]])
		seen[c.id] = path
		if c.scene == null:
			out.append("%s: нет сцены (карточка без сцены каталогом не читается)" % path)
		elif c.scene.resource_path != "%s/%s/%s.tscn" % [ROOMS_DIR, file_id, file_id]:
			out.append("%s: сцена %s, ожидается %s/%s/%s.tscn" % [path, c.scene.resource_path, ROOMS_DIR, file_id, file_id])
		if c.title == "" and not _is_builtin(c.id):
			out.append("%s: пустое название" % path)
	if cards_dir != CARDS_DIR:
		return out
	# Старое место карточек: data/rooms/<id>/<id>.tres
	for dn in DirAccess.get_directories_at(ROOMS_DIR):
		if dn == "cards":
			continue
		for f in DirAccess.get_files_at("%s/%s" % [ROOMS_DIR, dn]):
			if f.ends_with(".tres") or f.ends_with(".tres.remap"):
				out.append("%s/%s/%s: карточка не в data/rooms/cards/" % [ROOMS_DIR, dn, f])
	if not has(DEFAULT_ID):
		out.append("комнаты по умолчанию '%s' нет в каталоге" % DEFAULT_ID)
	return out


## Новый паспорт по id. Неизвестный id: комната по умолчанию
static func make(id: StringName) -> RoomConfig:
	var passport := _load_passport(id)
	if passport:
		# Комната из сцены: свой экземпляр паспорта (поверх общего ресурса RoomBuilder ничего не пишет, но варианты пишет в свой)
		var sc := passport.duplicate() as RoomConfig
		sc.id = id
		sc.variants = {}
		return sc
	var c := RoomConfig.new()
	match id:
		&"bench":
			# Стенд для прогонов: только стол (table_top по умолчанию 200 x 100 см), ни пола, ни стен, ни потолка, ни ламп комнаты.
			# Свет: Sun и SkyFill GFX. Границы камеры широкие, пола нет: упавшее с стола улетает вниз
			c.id = &"bench"
			c.shape = &"none"
			c.furnished = false
			c.show_stats = true
			c.window = {}
			c.door = {}
			c.size = Vector3(800.0, 400.0, 800.0)
			c.bounds = AABB(Vector3(-400.0, 3.0, -400.0), Vector3(800.0, 400.0, 800.0))
		&"cube":
			# Пустая коробка для текстур и импортированных элементов: без мебели, окна и двери
			c.id = &"cube"
			c.furnished = false
			c.size = Vector3(400.0, 250.0, 400.0)
			c.window = {}
			c.door = {}
			c.bounds = AABB(Vector3(-190.0, 3.0, -190.0), Vector3(380.0, 190.0, 380.0))
		&"attic":
			# Мансарда (RoomAttic): скос крыши вместо восточной стены, окна закрыты, свет только лампы дневного света.
			# Размеры и лампы подбираются здесь. Энергия ламп прикидочная (мир в см, затухание ~1/d), правится глазом в редакторе
			c.id = &"attic"
			c.shape = &"attic"
			c.size = Vector3(520.0, 250.0, 420.0)
			c.roof_top_x = 50.0
			c.window = {}   # окна и дверь рисует RoomAttic
			c.door = {}
			c.daylight = false
			c.ambient_mul = 0.5
			c.lamps = [
				# Две над макетом (с тенью), одна над диваном и ковром, одна под скосом над верстаком (без тени)
				{"x": -50.0, "z": 0.0, "len": 120.0, "axis": "z", "energy": 170.0, "shadow": true},
				{"x": 25.0, "z": 0.0, "len": 120.0, "axis": "z", "energy": 170.0, "shadow": true},
				{"x": -170.0, "z": 0.0, "len": 120.0, "axis": "z", "energy": 130.0, "shadow": false},
				{"x": 95.0, "z": -100.0, "len": 80.0, "axis": "z", "y": 178.0, "energy": 110.0, "shadow": false},
			]
			# Камера: коробка AABB, под скосом выше потолка нельзя, поэтому на восток только до края плоского потолка
			c.bounds = AABB(Vector3(-245.0, 3.0, -195.0), Vector3(300.0, 190.0, 390.0))
		_:
			c.id = DEFAULT_ID
	for b in BUILTIN:
		if b.id == c.id:
			c.title = b.title
			c.tip = b.tip
			c.dev_only = bool(b.get("dev_only", false))
	return c
