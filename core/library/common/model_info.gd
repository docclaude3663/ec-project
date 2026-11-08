@tool
class_name ModelInfo extends Resource

# XX claude-library (новый файл)
########################
## ModelInfo. Паспорт модели для Library (ATTN_22 §22.6.2, шаг L0)
########################
## Лежит отдельным ресурсом res://data/library/info/<key>.tres, ключ = EntitySetting.get_key().
## Сами объекты каталога не меняются. Поля появляются по шагам: зоны покраски (L3), детали и свет (L5), подстройка (L6).
## @tool: нужен линту каталога (tests/catalog_lint.gd), иначе в редакторе поля не читаются.

const DIR := "res://data/library/info/"
## Ориентир масштаба: 1 ю около 1 м прототипа (масштаб проекта 1:100, ATTN_20 §20.2, ATTN_TDD §9)
const PROTOTYPE_M_PER_UNIT := 1.0

@export var key: StringName = &""
## Название для игрока (может отличаться от EntitySetting.name)
@export var title := ""
@export_multiline var story := ""
## {railway, series, builder, country, years, role}: данные реального прототипа, заполняет автор
@export var prototype: Dictionary = {}
@export var scale_note := ""
@export var tags: PackedStringArray = PackedStringArray()
## {kind: free | xp | chapter | kit, xp: int, id: String}
@export var unlock: Dictionary = {"kind": "free"}
## Названия зон покраски: id зоны ("<имя меша>#<номер поверхности>") -> название. Без записи название берётся из меша
@export var zone_titles: Dictionary = {}


static func path_for(model_key: StringName) -> String:
	return DIR + String(model_key) + ".tres"


## Паспорт модели или null, если его нет
static func find(model_key: StringName) -> ModelInfo:
	var path := path_for(model_key)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ModelInfo


static func prototype_meters(units: float) -> float:
	return units * PROTOTYPE_M_PER_UNIT


func unlock_kind() -> String:
	return str(unlock.get("kind", "free"))


func xp_cost() -> int:
	return int(unlock.get("xp", 0))


## Одна строка про прототип из заполненных полей; пусто, если автор ничего не внёс
func prototype_line() -> String:
	var parts: Array[String] = []
	for k in ["railway", "series", "builder", "country", "years"]:
		var v := str(prototype.get(k, ""))
		if v != "":
			parts.append(v)
	return ", ".join(parts)
