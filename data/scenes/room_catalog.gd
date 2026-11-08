class_name RoomCatalog extends RefCounted

########################
## Каталог комнат: id -> паспорт (RoomConfig). Комната в памяти одна (RoomBuilder.switch_room пересобирает её).
########################
## Новая комната = запись в IDS и ветка в make(). Арт-версия подключается через RoomConfig.scene.

const DEFAULT_ID := &"kid_room_10"

## id и название для UI (карточки Room)
const IDS := [
	{"id": &"kid_room_10", "title": "Детская"},
	{"id": &"cube", "title": "Пустой куб"},
	{"id": &"attic", "title": "Мансарда"},
]


static func has(id: StringName) -> bool:
	for d in IDS:
		if d.id == id:
			return true
	return false


## Новый паспорт по id. Неизвестный id: комната по умолчанию
static func make(id: StringName) -> RoomConfig:
	var c := RoomConfig.new()
	match id:
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
