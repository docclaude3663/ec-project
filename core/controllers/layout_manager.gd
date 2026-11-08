extends Node
# class_name не задаём: это синглтон LYM (autoload), как TGM и PGM
###########################
## 💡 LYM - Системный сервис (autoload). Подмакетник: паспорт (LayoutConfig) и запросы по плите стола.
############################
# XX claude-table T0 (новый файл)
##
## ATTN_23. Сейчас плита это один прямоугольник из паспорта комнаты (RoomConfig.table_top, v1).
## В T1 плиту строят секции-Entity, и table_rect() начнёт считать по ним, а потребители (TGM.table_rect, домен воды)
## останутся прежними. Верх плиты всегда y = 0; ground, трак и опоры знают только про слой ground, не про секции.

## ⚡ Подмакетник изменился (секция, высота, опоры, загрузка сейва). Слушают опоры, границы камеры, домен воды
signal layout_changed

## Паспорт текущего макета. Заменяется целиком только через set_state / reset
var config := LayoutConfig.new()


## Ограничивающий прямоугольник плиты в мире (XZ), центр в (0, 0). Стартовая плита v1 берётся из паспорта комнаты.
## В T1 заменится объединением секций
func table_rect() -> Rect2:
	var size := RoomConfig.new().table_top
	if is_inside_tree():
		var rb := get_tree().get_first_node_in_group(&"room_root")
		if rb != null and rb.get("config") is RoomConfig:
			size = (rb.get("config") as RoomConfig).table_top
	return Rect2(-size * 0.5, size)


## Состояние для SavedGame.layout
func get_state() -> Dictionary:
	return config.get_state()


## Загрузка сейва. Пустой словарь (сейв до подмакетника): значения по умолчанию, стол как в v1
func set_state(d: Dictionary) -> void:
	config = LayoutConfig.new()
	if not d.is_empty():
		config.set_state(d)
	layout_changed.emit()


## Новый макет: всё по умолчанию
func reset() -> void:
	set_state({})
