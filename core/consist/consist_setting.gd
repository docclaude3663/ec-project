class_name ConsistSetting extends EntitySetting

###########################
## ConsistSetting. Кнопка каталога для шаблона состава
###########################
## Обёртка, чтобы шаблон ехал по тому же пути, что и объекты: теги, сортировка, ObjectButton, ToolbarController.
## Это не объект мира: компонентов нет, ставится головная часть (head), остальные части достраиваются
## по шаблону (этап 3). Создаётся в EntityCatalogProvider из ConsistTemplate.

const TAG := &"consist"

@export var template: ConsistTemplate

## Настройка головной части: из неё берётся призрак
var head: EntitySetting

## Настройки всех частей по порядку шаблона (part_settings[0] == head)
var part_settings: Array[EntitySetting] = []


## Шаблон игрока (лежит в user://), его можно переименовать и удалить. Встроенные шаблоны автора лежат в res://
func is_user() -> bool:
	return template != null and template.resource_path.begins_with(ConsistStore.USER_DIR)


## Кнопка шаблона. by_key: ключ объекта -> EntitySetting из каталога.
## null, если какой-то части шаблона нет в каталоге (кнопка не показывается, причина в warning)
static func from_template(tpl: ConsistTemplate, by_key: Dictionary) -> ConsistSetting:
	if tpl.parts.size() < 2:
		return null
	for p in tpl.parts:
		if not by_key.has(StringName(p.get("key", ""))):
			push_warning("Consist: в шаблоне '%s' нет объекта каталога %s, кнопка скрыта" % [tpl.name, p.get("key", "")])
			return null
	var s := ConsistSetting.new()
	s.template = tpl
	for p in tpl.parts:
		s.part_settings.append(by_key[StringName(p["key"])])
	s.head = s.part_settings[0]
	s.key = StringName("train.consist.%s" % tpl.id)
	s.category = &"train"
	s.tag = TAG
	s.name = tpl.name
	s.description = "Состав из %d частей: %s" % [tpl.parts.size(), ", ".join(_names(tpl, by_key))]
	s.icon = s.head.icon
	return s


static func _names(tpl: ConsistTemplate, by_key: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for p in tpl.parts:
		out.append((by_key[StringName(p["key"])] as EntitySetting).name)
	return out
