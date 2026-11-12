class_name VariantIO extends RefCounted

# XX claude-library (новый файл)
########################
## VariantIO. Чтение и запись данных игрока Library (ATTN_22 §22.6.2, шаг L0)
########################
## Всё в JSON под user://library/: profile.json и variants/<id>.json. Папку можно подменить (тесты).
## Битый или пустой файл не роняет: предупреждение в Output и пустой результат.
## Идентификатор исполнения идёт в имя файла, поэтому проверяется (ModelVariant.is_valid_id).

const DEFAULT_DIR := "user://library"
const PROFILE_FILE := "profile.json"
const VARIANTS_DIR := "variants"


static func profile_path(dir: String = DEFAULT_DIR) -> String:
	return dir.path_join(PROFILE_FILE)


static func variant_path(id: String, dir: String = DEFAULT_DIR) -> String:
	return dir.path_join(VARIANTS_DIR).path_join(id + ".json")


# --- профиль ---

static func save_profile(p: LibraryProfile, dir: String = DEFAULT_DIR) -> Error:
	return _write_json(profile_path(dir), p.to_dict())


## Профиль из файла; нет файла или он битый: пустой профиль
static func load_profile(dir: String = DEFAULT_DIR) -> LibraryProfile:
	var d: Variant = _read_json(profile_path(dir))
	if d is Dictionary:
		return LibraryProfile.from_dict(d)
	return LibraryProfile.new()


# --- исполнения ---

static func save_variant(v: ModelVariant, dir: String = DEFAULT_DIR) -> Error:
	if not ModelVariant.is_valid_id(v.id):
		push_warning("VariantIO: недопустимый id исполнения '%s'" % v.id)
		return ERR_INVALID_PARAMETER
	# data (байты PNG) в JSON не пишется: слой лежит файлом рядом (save_layers)
	return _write_json(variant_path(v.id, dir), _strip_data(v.to_dict()))


## Исполнение или null (нет файла, битый файл, недопустимый id)
static func load_variant(id: String, dir: String = DEFAULT_DIR) -> ModelVariant:
	if not ModelVariant.is_valid_id(id):
		return null
	var d: Variant = _read_json(variant_path(id, dir))
	if d is Dictionary:
		return ModelVariant.from_dict(d)
	return null


## Все исполнения; base не пустой: только этой модели. Порядок по имени, затем по id
static func list_variants(dir: String = DEFAULT_DIR, base: String = "") -> Array[ModelVariant]:
	var out: Array[ModelVariant] = []
	var folder := dir.path_join(VARIANTS_DIR)
	if not DirAccess.dir_exists_absolute(folder):
		return out
	for f in DirAccess.get_files_at(folder):
		if not f.ends_with(".json"):
			continue
		var v := load_variant(f.get_basename(), dir)
		if v == null:
			continue
		if base != "" and v.base != base:
			continue
		out.append(v)
	out.sort_custom(func(a: ModelVariant, b: ModelVariant) -> bool:
		if a.name != b.name:
			return a.name < b.name
		return a.id < b.id)
	return out


static func delete_variant(id: String, dir: String = DEFAULT_DIR) -> Error:
	if not ModelVariant.is_valid_id(id):
		return ERR_INVALID_PARAMETER
	var path := variant_path(id, dir)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.remove_absolute(path)
	save_layers(id, {}, dir)   # файлы слоёв кисти тоже
	return err


# --- слои кисти (PNG) ---

static func layer_dir(id: String, dir: String = DEFAULT_DIR) -> String:
	return dir.path_join(VARIANTS_DIR).path_join(id)


## Имя файла слоя: латиница, цифры, «_», «-» и расширение .png (имя идёт в путь)
static func is_valid_layer_file(file: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_-]+\\.png$")
	return re.search(file) != null


## Заменяет файлы слоёв исполнения: старые удаляются, записываются files (имя файла -> байты PNG). Пустой files чистит всё
static func save_layers(id: String, files: Dictionary, dir: String = DEFAULT_DIR) -> Error:
	if not ModelVariant.is_valid_id(id):
		return ERR_INVALID_PARAMETER
	for f in files:
		if not is_valid_layer_file(str(f)):
			push_warning("VariantIO: недопустимое имя файла слоя '%s'" % str(f))
			return ERR_INVALID_PARAMETER
	var folder := layer_dir(id, dir)
	if DirAccess.dir_exists_absolute(folder):
		for existing in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(existing))
		if files.is_empty():
			DirAccess.remove_absolute(folder)
	if files.is_empty():
		return OK
	DirAccess.make_dir_recursive_absolute(folder)
	for f in files:
		var fa := FileAccess.open(folder.path_join(str(f)), FileAccess.WRITE)
		if fa == null:
			return FileAccess.get_open_error()
		fa.store_buffer(files[f])
		fa.close()
	return OK


## Байты PNG слоя или пустой массив (нет файла, недопустимое имя)
static func load_layer_png(id: String, file: String, dir: String = DEFAULT_DIR) -> PackedByteArray:
	if not ModelVariant.is_valid_id(id) or not is_valid_layer_file(file):
		return PackedByteArray()
	var path := layer_dir(id, dir).path_join(file)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## Копия исполнения, где слои кисти, у которых есть файл, получили PNG внутри словаря (поле data): для сейва макета и игры
static func embed_layers(variant: Dictionary, id: String, dir: String = DEFAULT_DIR) -> Dictionary:
	var out := variant.duplicate(true)
	var pv: Variant = out.get("paint")
	if not (pv is Dictionary):
		return out
	for layer in PaintData.texture_layers(pv):
		if layer.has("data") or not layer.has("file"):
			continue
		var bytes := load_layer_png(id, str(layer["file"]), dir)
		if not bytes.is_empty():
			layer["data"] = bytes
	return out


static func _strip_data(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var pv: Variant = out.get("paint")
	if pv is Dictionary:
		for layer in PaintData.texture_layers(pv):
			layer.erase("data")
	return out


# --- JSON ---

static func _write_json(path: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_warning("VariantIO: не удалось записать %s (код %d)" % [path, err])
		return err
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK


## Содержимое файла или null: нет файла, пустой, не JSON или не словарь
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("VariantIO: не удалось открыть %s (код %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("VariantIO: %s: не JSON (строка %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not (json.data is Dictionary):
		push_warning("VariantIO: %s: ожидался словарь" % path)
		return null
	return json.data
