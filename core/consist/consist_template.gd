class_name ConsistTemplate extends Resource

###########################
## ConsistTemplate. Шаблон состава: список частей, которые ставятся вместе
###########################
## Хранит только то, чем состав отличается от набора отдельных вагонов: какие объекты каталога, в каком порядке
## и через какое расстояние. Сами части остаются обычными EntitySetting и ставятся фабрикой как обычно.
## Порядок частей: от головной к хвостовой. Шаблон игрока лежит в user://library/consists/ (ConsistStore),
## встроенные шаблоны автора лежат в res:// рядом с данными (тот же формат).

## Стабильный идентификатор, он же имя файла
@export var id: StringName = &""

## Подпись кнопки в каталоге
@export var name: String = ""

## Части от головной: {"key": String, "reversed": bool, "spacing": float}
##   key      - EntitySetting.get_key() объекта каталога
##   reversed - часть стоит передом назад относительно «стандартного» направления состава
##              (состав записан от головной части, стандартное направление - от FRONT к REAR)
##   spacing  - расстояние между центром этой части и центром предыдущей по прямой, м (у головной 0)
@export var parts: Array[Dictionary] = []


## Ключи объектов каталога по порядку
func get_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for p in parts:
		out.append(String(p.get("key", "")))
	return out
