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
		_:
			c.id = DEFAULT_ID
	return c
