class_name RoomConfig extends Resource

########################
## Паспорт комнаты. Значения по умолчанию = kid_room_10 (комната ребёнка 10 лет).
########################
## Единицы: 1 u = 1 см реального стола (TDD §9). Центр комнаты по X/Z в (0, 0), столешница подмакетника на y = 0.
## Сейчас по этим данным RoomBuilder строит greybox. Арт-версия (S7) подключается через scene.

@export var id: StringName = &"kid_room_10"
## Арт-версия комнаты. Пусто = greybox, который строит RoomBuilder
@export var scene: PackedScene

@export_category("Room")
## Внутренний размер: X ширина, Y высота, Z глубина
@export var size := Vector3(480.0, 250.0, 380.0)
## Уровень пола (стол 0.5 м: столешница на y = 0)
@export var floor_y := -50.0
@export var wall_thickness := 10.0
## Проёмы: x - центр вдоль стены, w / h - размер, sill - высота низа от пола.
## Окно в северной стене (-Z), дверь в южной (+Z)
## Окно в северной стене. Пятно солнца на столе: ширина окна ≈ ширина пятна, высота окна / tan(высота солнца) ≈ глубина пятна
@export var window := {"x": 0.0, "w": 170.0, "sill": 80.0, "h": 140.0}
@export var door := {"x": 100.0, "w": 80.0, "sill": 0.0, "h": 200.0}

@export_category("Table (подмакетник v1)")
## Столешница: X, Z
@export var table_top := Vector2(200.0, 100.0)
@export var table_top_thickness := 5.0
@export var table_leg := 6.0

@export_category("Camera")
## Границы, в которых держим камеру (CameraBounds). Низ выше столешницы, верх ниже потолка
@export var bounds := AABB(Vector3(-230.0, 3.0, -180.0), Vector3(460.0, 190.0, 360.0))

## slot -> id варианта (цвет стен, набор постеров, покрывало). Заполняется с S7
@export var variants := {}
