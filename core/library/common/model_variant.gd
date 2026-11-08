class_name ModelVariant extends RefCounted

# XX claude-library (новый файл)
########################
## ModelVariant. Исполнение модели: покраска, детали, свет, подстройка (ATTN_22 §22.6.2, шаг L0)
########################
## Хранится JSON (user://library/variants/<id>.json), не .tres: .tres из user:// может нести скрипты (ATTN_22 F7).
## Поле v обязательно. Неизвестные поля не теряются при перезаписи: старая версия игры не стирает данные новой.
## Здесь только данные; применение к экземпляру сцены делает VariantApplier (шаг L3).

const VERSION := 1
const KNOWN := ["v", "id", "base", "name", "paint", "decals", "parts", "fit", "tuning", "built"]

var id := ""
## key модели (EntitySetting.get_key()), к которой относится исполнение
var base := ""
var name := ""
## Покраска, схема v2: {v: 2, layers: [...]}, см. PaintData
var paint: Dictionary = {}
var decals: Array = []
## слот -> опция
var parts: Dictionary = {}
## свет и механизмы: id -> {on: bool, color: "#rrggbb"}
var fit: Dictionary = {}
## поле -> значение (шаг L6)
var tuning: Dictionary = {}
var built := false

var _extra: Dictionary = {}
var _version := VERSION


## Новый идентификатор: шестнадцатеричные цифры времени и случайное число. Безопасен для имени файла
static func make_id() -> String:
	return "%x%04x" % [int(Time.get_unix_time_from_system()), randi() & 0xffff]


## Идентификатор идёт в имя файла: только латиница, цифры, «_» и «-», до 64 знаков
static func is_valid_id(s: String) -> bool:
	if s.is_empty() or s.length() > 64:
		return false
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_-]+$")
	return re.search(s) != null


func to_dict() -> Dictionary:
	var d := _extra.duplicate(true)
	d["v"] = maxi(_version, VERSION)
	d["id"] = id
	d["base"] = base
	d["name"] = name
	d["paint"] = paint.duplicate(true)
	d["decals"] = decals.duplicate(true)
	d["parts"] = parts.duplicate(true)
	d["fit"] = fit.duplicate(true)
	d["tuning"] = tuning.duplicate(true)
	d["built"] = built
	return d


static func from_dict(d: Dictionary) -> ModelVariant:
	var v := ModelVariant.new()
	v._version = int(d.get("v", VERSION))
	v.id = str(d.get("id", ""))
	v.base = str(d.get("base", ""))
	v.name = str(d.get("name", ""))
	v.paint = _dict_of(d.get("paint"))
	v.decals = _array_of(d.get("decals"))
	v.parts = _dict_of(d.get("parts"))
	v.fit = _dict_of(d.get("fit"))
	v.tuning = _dict_of(d.get("tuning"))
	v.built = bool(d.get("built", false))
	for k in d:
		if not KNOWN.has(str(k)):
			v._extra[k] = d[k]
	return v


func duplicate_variant() -> ModelVariant:
	return ModelVariant.from_dict(to_dict())


static func _dict_of(x: Variant) -> Dictionary:
	if x is Dictionary:
		return (x as Dictionary).duplicate(true)
	return {}


static func _array_of(x: Variant) -> Array:
	if x is Array:
		return (x as Array).duplicate(true)
	return []
