class_name LayoutConfig extends Resource

# XX claude-table T0 (новый файл)
########################
## Паспорт подмакетника (ATTN_23): опоры, высота, материал, проход. Один на макет, хранится в SavedGame.layout.
########################
## Секции плиты это Entity (T1), здесь только общие настройки. Размер стартовой плиты берётся из RoomConfig.table_top
## (значение v1 остаётся источником миграции старых сейвов).
## Единицы: 1 u = 1 см стола. Верх плиты всегда на y = 0 (ATTN_23 §23.2), поэтому высота стола это глубина пола.

enum Support { LEGS, PLINTH, WALL }

## Версия формата в сейве. Пустой словарь сейва = старый макет (до подмакетника), он читается значениями по умолчанию
const VERSION := 1
const HEIGHT_MIN := 5.0
const HEIGHT_MAX := 130.0

## Опоры: ножки, низкая рама на полу, кронштейны к стене (T3 и далее)
@export var support: Support = Support.LEGS
## Высота верха плиты над полом, u (из неё считается floor_y в T3). 50 = как в v1
@export_range(5.0, 130.0, 1.0) var height := 50.0
## Материал плиты (TableStyle, T6). Пока только метка
@export var style: StringName = &"chipboard"
## Проход вокруг стола с рабочих сторон, u (лимит площади в T2)
@export var aisle_min := 60.0


## Состояние для сейва. Всегда непустой (есть version): по нему загрузка отличает новый сейв от старого
func get_state() -> Dictionary:
	return {
		"version": VERSION,
		"support": int(support),
		"height": height,
		"style": String(style),
		"aisle_min": aisle_min,
	}


## Читает состояние из сейва. Недостающие ключи остаются значениями по умолчанию, лишние игнорируются
func set_state(d: Dictionary) -> void:
	var def := LayoutConfig.new()
	support = clampi(int(d.get("support", int(def.support))), 0, Support.size() - 1) as Support
	height = clampf(float(d.get("height", def.height)), HEIGHT_MIN, HEIGHT_MAX)
	style = StringName(String(d.get("style", String(def.style))))
	aisle_min = maxf(0.0, float(d.get("aisle_min", def.aisle_min)))
