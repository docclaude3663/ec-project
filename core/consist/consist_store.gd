class_name ConsistStore extends RefCounted

###########################
## ConsistStore. Запись и чтение пользовательских шаблонов составов
###########################
## Шаблоны игрока: user://library/consists/<id>.tres (в экспортированной игре res:// только для чтения).
## Запись берёт весь сцепленный состав, в котором стоит выбранный вагон (C_Coupler.get_ordered_consist).

const USER_DIR := "user://library/consists/"
## Шаблоны автора, поставляются с игрой (тот же формат, что у шаблонов игрока)
const BUILTIN_DIR := "res://data/trains/consists/"
const MAX_NAME_PARTS := 2   # сколько названий частей показывать в подписи по умолчанию


## Записывает состав выбранного вагона. Результат: {"ok": bool, "name": String, "path": String, "error": String}
static func record(entity: Entity) -> Dictionary:
	var coupler := entity.get_comp(C_Coupler) as C_Coupler if entity else null
	if coupler == null:
		return _fail("у объекта нет сцепки")
	var chain := coupler.get_ordered_consist()
	if chain.size() < 2:
		return _fail("состав из одной части: сцепите вагоны")

	var tpl := ConsistTemplate.new()
	var names: Array[String] = []
	var prev: Entity = null
	for item in chain:
		var e: Entity = item["entity"]
		var idc := e.get_comp(C_Identity) as C_Identity
		if idc == null or idc.setting == null:
			return _fail("у части %s нет объекта каталога" % e.name)
		var spacing := 0.0 if prev == null else prev.global_position.distance_to(e.global_position)
		tpl.parts.append({
			"key": String(idc.setting.get_key()),
			"reversed": item["reversed"],
			"spacing": snappedf(spacing, 0.001),
		})
		names.append(idc.setting.name)
		prev = e

	tpl.name = _default_name(names)
	tpl.id = _free_id()
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := USER_DIR + String(tpl.id) + ".tres"
	var err := ResourceSaver.save(tpl, path)
	if err != OK:
		return _fail("не удалось сохранить файл (код %d)" % err)
	print("[Consist] записан шаблон: ", path, " ", tpl.get_keys())
	return {"ok": true, "name": tpl.name, "path": path, "error": ""}


## Все шаблоны: сначала встроенные, потом игрока, каждая папка по имени файла
static func load_all() -> Array[ConsistTemplate]:
	var out: Array[ConsistTemplate] = []
	for dir in [BUILTIN_DIR, USER_DIR]:
		for path in EntityCatalogProvider.list_resources(dir):
			var tpl := load(path) as ConsistTemplate
			if tpl != null:
				out.append(tpl)
	return out


## Переименовывает шаблон игрока. Результат: пустая строка или причина отказа
static func rename(tpl: ConsistTemplate, new_name: String) -> String:
	new_name = new_name.strip_edges()
	if new_name == "":
		return "имя не может быть пустым"
	if not tpl.resource_path.begins_with(USER_DIR):
		return "встроенный шаблон переименовывается в его .tres"
	tpl.name = new_name
	var err := ResourceSaver.save(tpl, tpl.resource_path)
	return "" if err == OK else "не удалось сохранить файл (код %d)" % err


## Удаляет шаблон игрока с диска. Результат: пустая строка или причина отказа
static func delete(tpl: ConsistTemplate) -> String:
	if not tpl.resource_path.begins_with(USER_DIR):
		return "встроенный шаблон удаляется вместе с его .tres"
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(tpl.resource_path))
	return "" if err == OK else "не удалось удалить файл (код %d)" % err


static func _default_name(names: Array[String]) -> String:
	if names.size() <= MAX_NAME_PARTS:
		return " + ".join(names)
	return "%s ... %s (%d)" % [names[0], names[names.size() - 1], names.size()]


static func _free_id() -> StringName:
	var base := "consist_%d" % int(Time.get_unix_time_from_system())
	var id := base
	var n := 1
	while FileAccess.file_exists(USER_DIR + id + ".tres"):
		n += 1
		id = "%s_%d" % [base, n]
	return StringName(id)


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "name": "", "path": "", "error": why}
