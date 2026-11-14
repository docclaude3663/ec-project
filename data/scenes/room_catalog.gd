class_name RoomCatalog extends RefCounted

########################
## Каталог комнат: id -> паспорт (RoomConfig). Комната в памяти одна (RoomBuilder.switch_room пересобирает её).
########################
## Два источника:
##  1. Папка data/rooms/<id>/<id>.tres: паспорт со сценой (RoomConfig.scene, корень RoomRoot). Сцену правят в редакторе.
##     Новая комната из сцены = новая папка, кода менять не нужно, карточка в Observe появляется сама.
##  2. BUILTIN: процедурные комнаты, которые строит RoomBuilder кодом (ветки в make()). Если рядом лежит data/rooms/<id>/<id>.tres
##     с тем же id, вместо процедурной берётся сцена. Сцену из процедурной комнаты записывает кнопка «Комнату в сцену» (F3 → Toggles, только редактор).

const DEFAULT_ID := &"kid_room_10"
const ROOMS_DIR := "res://data/rooms"

## Процедурные комнаты: id, название и подсказка карточки
const BUILTIN := [
	{"id": &"kid_room_10", "title": "Детская", "tip": "Заменяет комнату целиком (в памяти одна)"},
	{"id": &"cube", "title": "Пустой куб", "tip": "Пустая коробка для текстур и импорта. Заменяет комнату целиком"},
	{"id": &"bench", "title": "Стенд (только стол)", "tip": "Тестовая: только стол 1x2 м, без пола, стен и потолка. Включает оверлей статистики. Заменяет комнату целиком"},
	{"id": &"attic", "title": "Мансарда", "tip": "Скос крыши, окна закрыты, свет только лампы дневного света. Заменяет комнату целиком"},
]


## Все комнаты для карточек: [{id, title, tip}]. Сначала встроенные (в своём порядке), затем остальные папки data/rooms по алфавиту
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BUILTIN:
		var d: Dictionary = b.duplicate()
		var c := _load_passport(b.id)
		if c:
			if c.title != "":
				d.title = c.title
			if c.tip != "":
				d.tip = c.tip
		out.append(d)
	var dirs := []
	if DirAccess.dir_exists_absolute(ROOMS_DIR):
		dirs = Array(DirAccess.get_directories_at(ROOMS_DIR))
	dirs.sort()
	for dn in dirs:
		var id := StringName(dn)
		if _is_builtin(id):
			continue
		var c := _load_passport(id)
		if c == null:
			continue
		out.append({"id": id, "title": c.title if c.title != "" else String(id), "tip": c.tip})
	return out


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
	return "%s/%s/%s.tres" % [ROOMS_DIR, id, id]


## Паспорт из data/rooms (общий ресурс, не менять). null: папки или паспорта нет, или в нём нет сцены
static func _load_passport(id: StringName) -> RoomConfig:
	var path := _passport_path(id)
	if not ResourceLoader.exists(path):
		return null
	var c := load(path) as RoomConfig
	if c == null or c.scene == null:
		return null
	return c


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
	return c
