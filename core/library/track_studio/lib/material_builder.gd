class_name TrackMaterialBuilder extends RefCounted

########################
## Материалы из наборов текстур (ATTN_20, шаг T2)
########################
## Без интерфейса. Разбирает папку с PBR-набором по именам файлов (ambientCG, Poly Haven, свои),
## проверяет настройки импорта, собирает StandardMaterial3D. Вход сборки это Texture2D,
## а не пути: загрузчик можно заменить (файлы игрока из user://) без правки сборщика.
## Единица длины тайла: ю. Масштаб проекта 1:100, ориентир 1 ю около 1 м прототипа,
## физический размер тайла ambientCG около 1 м, поэтому тайл 1 ю даёт натуральный размер деталей.

const ROLE_TITLES := {
	"albedo": "Цвет", "normal": "Нормаль", "roughness": "Шероховатость",
	"metallic": "Металличность", "ao": "AO", "height": "Высота", "orm": "ORM (AO/rough/metal)",
}

# Суффиксы имён файлов (нижний регистр, после последнего "_"). Порядок внутри роли не важен
const SUFFIXES := {
	"albedo": ["color", "albedo", "basecolor", "base_color", "diffuse", "diff", "col"],
	"normal_gl": ["normalgl", "normal_gl", "nor_gl", "normal", "nrm", "nor"],
	"normal_dx": ["normaldx", "normal_dx", "nor_dx"],
	"roughness": ["roughness", "rough"],
	"metallic": ["metalness", "metallic", "metal"],
	"ao": ["ambientocclusion", "ao", "occlusion"],
	"height": ["displacement", "height", "disp"],
	"orm": ["orm", "arm"],
}
const IMAGE_EXT := ["jpg", "jpeg", "png", "webp", "tga", "bmp", "exr"]

## Параметры по умолчанию. tile в ю (x вдоль пути, y поперек); для triplanar это размер тайла по всем осям
const DEFAULTS := {
	"tint": Color.WHITE,
	"roughness": 1.0,      # множитель карты шероховатости
	"metallic": -1.0,      # -1 = авто (есть карта: 1, нет карты: 0); иначе множитель карты или само значение
	"normal_scale": 1.0,
	"use_ao": true,
	"ao_light_affect": 0.0,
	"use_height": false,
	"height_scale": 0.05,
	"triplanar": false,
	"vertex_color": false,  # множить цвет на вершинный цвет меша (подкладки шпалы другого цвета)
	"mesh_uv_units": false, # UV меша в ю (меши генератора): тайл через uv1_scale. false = UV как есть
	"tile": Vector2(1.0, 1.0),
}

## Заготовки по роли материала в стиле
const PRESETS := {
	"rail": {"metallic": 1.0, "roughness": 1.0, "tile": Vector2(1.0, 1.0), "triplanar": false, "use_ao": false},
	"ballast": {"metallic": -1.0, "roughness": 1.0, "tile": Vector2(1.0, 1.0), "triplanar": false, "use_ao": true},
	"sleeper": {"metallic": -1.0, "roughness": 1.0, "tile": Vector2(1.0, 1.0), "triplanar": false, "mesh_uv_units": true, "vertex_color": true, "use_ao": true},
}


# ==========================================
# Разбор папки
# ==========================================

## Подпапки dir (имена), по алфавиту
static func list_sets(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for d in da.get_directories():
		out.append(d)
	out.sort()
	return out


## Карты набора: {albedo, normal, roughness, metallic, ao, height, orm: путь, normal_is_dx: bool}.
## Только найденные ключи. Нормаль OpenGL предпочтительнее DirectX
static func scan(dir: String) -> Dictionary:
	var found := {}
	var da := DirAccess.open(dir)
	if da == null:
		return found
	var normal_gl := ""
	var normal_dx := ""
	for f in da.get_files():
		if not IMAGE_EXT.has(f.get_extension().to_lower()):
			continue
		var role := _role_of(f.get_basename())
		if role.is_empty():
			continue
		var path := dir.path_join(f)
		match role:
			"normal_gl":
				normal_gl = path
			"normal_dx":
				normal_dx = path
			_:
				if not found.has(role):
					found[role] = path
	if not normal_gl.is_empty():
		found["normal"] = normal_gl
		found["normal_is_dx"] = false
	elif not normal_dx.is_empty():
		found["normal"] = normal_dx
		found["normal_is_dx"] = true
	return found


## Роль по имени файла без расширения. "" = не карта (превью, IdMask и т. п.)
static func _role_of(base: String) -> String:
	var parts := base.to_lower().split("_")
	# Poly Haven и другие дописывают разрешение в конце: rock_diff_1k
	if parts.size() > 1 and _is_resolution(parts[parts.size() - 1]):
		parts.remove_at(parts.size() - 1)
	if parts.is_empty():
		return ""
	var last: String = parts[parts.size() - 1]
	var last2: String = (parts[parts.size() - 2] + "_" + last) if parts.size() > 1 else ""
	for role in SUFFIXES:
		var list: Array = SUFFIXES[role]
		if list.has(last2) or list.has(last):
			# "normal" без суффикса GL/DX считаем OpenGL, но точный DX сильнее
			return role
	return ""


static func _is_resolution(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9]+k$")
	return re.search(s) != null


# ==========================================
# Импорт текстур
# ==========================================

## Читает <файл>.import. {ok, mipmaps, normal_map (0 detect, 1 enable, 2 disable), mode}
static func import_info(tex_path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(tex_path + ".import") != OK:
		return {"ok": false}
	return {
		"ok": true,
		"mipmaps": bool(cfg.get_value("params", "mipmaps/generate", false)),
		"normal_map": int(cfg.get_value("params", "compress/normal_map", 0)),
		"mode": int(cfg.get_value("params", "compress/mode", 0)),
	}


## Замечания по импорту набора: массив строк. Пусто = всё в порядке
static func import_warnings(found: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key in ["albedo", "normal", "roughness", "metallic", "ao", "height", "orm"]:
		if not found.has(key):
			continue
		var info := import_info(found[key])
		if not info["ok"]:
			out.append("%s: нет файла .import (текстура ещё не импортирована?)" % String(found[key]).get_file())
			continue
		if not info["mipmaps"]:
			out.append("%s: мипмапы выключены, вдали будет мерцать" % String(found[key]).get_file())
		if key == "normal" and info["normal_map"] != 1:
			out.append("%s: Normal Map не Enable (сейчас %s)" % [String(found[key]).get_file(), ["Detect", "Enable", "Disabled"][clampi(info["normal_map"], 0, 2)]])
	return out


## Правит .import файлов набора: мипмапы включить, у нормали Normal Map = Enable. Режим сжатия не трогаем.
## Godot переимпортирует сам при возврате фокуса в редактор. Возвращает список изменённых файлов
static func fix_import(found: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	for key in ["albedo", "normal", "roughness", "metallic", "ao", "height", "orm"]:
		if not found.has(key):
			continue
		var path: String = found[key] + ".import"
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		var dirty := false
		if not bool(cfg.get_value("params", "mipmaps/generate", false)):
			cfg.set_value("params", "mipmaps/generate", true)
			dirty = true
		if key == "normal" and int(cfg.get_value("params", "compress/normal_map", 0)) != 1:
			cfg.set_value("params", "compress/normal_map", 1)
			dirty = true
		if dirty and cfg.save(path) == OK:
			changed.append(String(found[key]).get_file())
	return changed


## DirectX-нормаль (Y-) в OpenGL (Y+): инвертирует зелёный канал, пишет <имя>_GL.png рядом. Возвращает путь или "" при ошибке
static func convert_dx_to_gl(src: String) -> String:
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return ""
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var i := 1
	while i < data.size():
		data[i] = 255 - data[i]
		i += 3
	var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, data)
	var dst := src.get_basename().replace("NormalDX", "Normal").replace("normal_dx", "normal").replace("nor_dx", "nor") + "_GL.png"
	return dst if out.save_png(dst) == OK else ""


# ==========================================
# Сборка материала
# ==========================================

## Заготовка параметров для роли ("rail", "ballast", "sleeper"): DEFAULTS + PRESETS
static func preset(role: String) -> Dictionary:
	var p: Dictionary = DEFAULTS.duplicate(true)
	if PRESETS.has(role):
		for k in PRESETS[role]:
			p[k] = PRESETS[role][k]
	return p


## tex: {albedo, normal, roughness, metallic, ao, height, orm: Texture2D}. params: см. DEFAULTS
static func build(tex: Dictionary, params: Dictionary) -> StandardMaterial3D:
	var p: Dictionary = DEFAULTS.duplicate(true)
	p.merge(params, true)
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color = p["tint"]
	if tex.has("albedo"):
		m.albedo_texture = tex["albedo"]

	if tex.has("orm"):
		# Упакованная карта: R = AO, G = roughness, B = metallic
		if p["use_ao"]:
			m.ao_enabled = true
			m.ao_texture = tex["orm"]
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = tex["orm"]
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = tex["orm"]
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	else:
		if tex.has("roughness"):
			m.roughness_texture = tex["roughness"]
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		if tex.has("metallic"):
			m.metallic_texture = tex["metallic"]
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		if tex.has("ao") and p["use_ao"]:
			m.ao_enabled = true
			m.ao_texture = tex["ao"]
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = p["roughness"]
	var has_metal := tex.has("metallic") or tex.has("orm")
	var metal: float = p["metallic"]
	m.metallic = metal if metal >= 0.0 else (1.0 if has_metal else 0.0)
	if m.ao_enabled:
		m.ao_light_affect = p["ao_light_affect"]

	if tex.has("normal"):
		m.normal_enabled = true
		m.normal_texture = tex["normal"]
		m.normal_scale = p["normal_scale"]

	if tex.has("height") and p["use_height"]:
		m.heightmap_enabled = true
		m.heightmap_texture = tex["height"]
		m.heightmap_scale = p["height_scale"]

	if p["vertex_color"]:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true

	if p["triplanar"]:
		# Координаты в локальных единицах меша (ю): один тайл = tile ю
		var t: Vector2 = p["tile"]
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3(1.0 / maxf(t.x, 0.001), 1.0 / maxf(t.y, 0.001), 1.0 / maxf(t.x, 0.001))
	elif p["mesh_uv_units"]:
		var t2: Vector2 = p["tile"]
		m.uv1_scale = Vector3(1.0 / maxf(t2.x, 0.001), 1.0 / maxf(t2.y, 0.001), 1.0)
	return m


## Загружает текстуры, найденные scan(), в словарь роль -> Texture2D
static func load_textures(found: Dictionary) -> Dictionary:
	var tex := {}
	for key in ["albedo", "normal", "roughness", "metallic", "ao", "height", "orm"]:
		if found.has(key):
			var t := ResourceLoader.load(found[key]) as Texture2D
			if t:
				tex[key] = t
	return tex


## Запоминает в метаданных материала, как он собран (для повторного открытия в студии)
static func stamp(mat: Material, role: String, dir: String, params: Dictionary) -> void:
	mat.set_meta("track_role", role)
	mat.set_meta("track_source", dir)
	mat.set_meta("track_params", params.duplicate(true))


# ==========================================
# Упаковка ORM и чистка набора
# ==========================================

## Упаковывает AO, шероховатость и металличность в один RGB PNG: R = AO, G = roughness, B = metallic.
## Нет карты: AO и roughness = 1, metallic = 0. Размер по первой найденной карте, остальные подгоняются.
## Возвращает Error (OK = 0). В материале ORM заменяет три текстуры одной (меньше памяти и выборок)
static func pack_orm(found: Dictionary, out_path: String) -> int:
	var out := orm_image(found)
	if out == null:
		return ERR_FILE_NOT_FOUND
	return out.save_png(out_path)


## Картинка ORM из карт набора (R = AO, G = roughness, B = metallic) или null, если карт нет
static func orm_image(found: Dictionary) -> Image:
	var maps := {}
	var w := 0
	var h := 0
	for key in ["ao", "roughness", "metallic"]:
		if not found.has(key):
			continue
		var img := Image.load_from_file(found[key])
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_L8)
		if w == 0:
			w = img.get_width()
			h = img.get_height()
		elif img.get_width() != w or img.get_height() != h:
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		maps[key] = img.get_data()
	if maps.is_empty():
		return null
	var count := w * h
	var data := PackedByteArray()
	data.resize(count * 3)
	var ao: PackedByteArray = maps.get("ao", PackedByteArray())
	var ro: PackedByteArray = maps.get("roughness", PackedByteArray())
	var me: PackedByteArray = maps.get("metallic", PackedByteArray())
	var has_ao := not ao.is_empty()
	var has_ro := not ro.is_empty()
	var has_me := not me.is_empty()
	for i in count:
		var o := i * 3
		data[o] = ao[i] if has_ao else 255
		data[o + 1] = ro[i] if has_ro else 255
		data[o + 2] = me[i] if has_me else 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)


## Куда писать ORM набора: <имя папки>_ORM.png рядом с картами
static func orm_path(dir: String) -> String:
	return dir.path_join(dir.get_file() + "_ORM.png")


## Файлы набора, которые студии не нужны: [{path, size, why}] (у каждого есть парный .import, он удаляется вместе).
## include_height: считать лишней карту высоты (parallax в студии выключен по умолчанию).
## Если рядом есть ORM, отдельные AO, шероховатость и металличность тоже в списке
static func cleanup_candidates(dir: String, include_height := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	var found := scan(dir)
	var has_orm := found.has("orm")
	var keep := {}
	var keep_keys := ["albedo", "normal", "orm"]
	if not has_orm:
		keep_keys.append_array(["roughness", "metallic", "ao"])
	if not include_height:
		keep_keys.append("height")
	for k in keep_keys:
		if found.has(k):
			keep[found[k]] = true
	for f in da.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "import" or ext == "uid":
			continue
		var path := dir.path_join(f)
		if keep.has(path):
			continue
		var why := ""
		if IMAGE_EXT.has(ext):
			var role := _role_of(f.get_basename())
			match role:
				"":
					why = "изображение без роли (превью, маска)"
				"normal_dx", "normal_gl":
					why = "нормаль в другом формате, используется %s" % String(found.get("normal", "")).get_file()
				"height":
					why = "карта высоты (parallax выключен)"
				"roughness", "metallic", "ao":
					why = "упакована в ORM"
				_:
					why = ""   # дубликат нужной роли: не трогаем
		elif ["blend", "mtlx", "usdc", "usd", "usda", "usdz", "fbx", "obj", "mtl"].has(ext):
			why = "исходник 3D или материал ambientCG"
		elif ext == "tres":
			why = "готовый материал ambientCG (с parallax), студия собирает свой"
		if why.is_empty():
			continue
		var size := 0
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa:
			size = fa.get_length()
		out.append({"path": path, "size": size, "why": why})
	return out


## Удаляет файлы и их .import. Только внутри base_dir. Возвращает число удалённых файлов
static func delete_files(items: Array, base_dir: String) -> int:
	var n := 0
	for it in items:
		var path: String = it["path"]
		if not path.begins_with(base_dir) or path.contains(".."):
			continue
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK:
			n += 1
		if FileAccess.file_exists(path + ".import"):
			DirAccess.remove_absolute(path + ".import")
	return n


# ==========================================
# Конвертация набора в WebP
# ==========================================

## Имя новой папки: токен JPG/JPEG/PNG в имени набора заменяется на WebP (Concrete030_1K-JPG -> Concrete030_1K-WebP),
## если токена нет, дописывается -WebP
static func webp_set_name(set_name: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)(jpe?g|png)")
	var m := re.search_all(set_name)
	if m.is_empty():
		return set_name + "-WebP"
	var last: RegExMatch = m[m.size() - 1]
	return set_name.substr(0, last.get_start()) + "WebP" + set_name.substr(last.get_end())


## Пишет рядом с набором dir новую папку с WebP: цвет и нормаль (GL) отдельными файлами, AO, шероховатость и
## металличность одним ORM (если карт две и больше, иначе каждая отдельным серым файлом). Высота пропускается.
## opts: quality (0..1, для цвета и всего с потерями), normal_lossless, orm_lossless.
## Возвращает {ok, dir, files: PackedStringArray, bytes_before, bytes_after, error}
static func convert_set_to_webp(dir: String, opts: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "dir": "", "files": PackedStringArray(), "bytes_before": 0, "bytes_after": 0, "error": ""}
	var found := scan(dir)
	if found.is_empty():
		res["error"] = "в наборе нет карт"
		return res
	var q: float = float(opts.get("quality", 0.9))
	var normal_ll: bool = bool(opts.get("normal_lossless", true))
	var orm_ll: bool = bool(opts.get("orm_lossless", true))
	var new_name := webp_set_name(dir.get_file())
	var out_dir := dir.get_base_dir().path_join(new_name)
	if out_dir == dir:
		res["error"] = "не удалось придумать имя новой папки"
		return res
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir)) not in [OK, ERR_ALREADY_EXISTS]:
		res["error"] = "не удалось создать " + out_dir
		return res
	res["dir"] = out_dir
	var used := {}   # исходные файлы, попавшие в расчёт размера
	var jobs: Array = []   # {name, image, lossy}

	if found.has("albedo"):
		var img := Image.load_from_file(found["albedo"])
		if img != null and not img.is_empty():
			jobs.append({"name": "Color", "image": img, "lossy": true})
			used[found["albedo"]] = true
	if found.has("normal"):
		var img := Image.load_from_file(found["normal"])
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGB8)
			if found.get("normal_is_dx", false):
				var data := img.get_data()
				var i := 1
				while i < data.size():
					data[i] = 255 - data[i]
					i += 3
				img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, data)
			jobs.append({"name": "NormalGL", "image": img, "lossy": not normal_ll})
			used[found["normal"]] = true
	var packed := {}
	for k in ["ao", "roughness", "metallic"]:
		if found.has(k):
			packed[k] = found[k]
	if found.has("orm"):
		var img := Image.load_from_file(found["orm"])
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGB8)
			jobs.append({"name": "ORM", "image": img, "lossy": not orm_ll})
			used[found["orm"]] = true
	elif packed.size() >= 2:
		var orm := orm_image(packed)
		if orm != null:
			jobs.append({"name": "ORM", "image": orm, "lossy": not orm_ll})
			for k in packed:
				used[packed[k]] = true
	else:
		for k in packed:
			var img := Image.load_from_file(packed[k])
			if img != null and not img.is_empty():
				img.convert(Image.FORMAT_L8)
				jobs.append({"name": {"ao": "AmbientOcclusion", "roughness": "Roughness", "metallic": "Metalness"}[k], "image": img, "lossy": not orm_ll})
				used[packed[k]] = true

	var files := PackedStringArray()
	for job in jobs:
		var path := out_dir.path_join("%s_%s.webp" % [new_name, job["name"]])
		var err: int = (job["image"] as Image).save_webp(path, bool(job["lossy"]), q)
		if err != OK:
			res["error"] = "не записан %s (код %d)" % [path.get_file(), err]
			return res
		files.append(path.get_file())
		res["files"] = files
		res["bytes_after"] += _file_size(path)
	for src in used:
		res["bytes_before"] += _file_size(src)
	res["ok"] = not files.is_empty()
	if not res["ok"]:
		res["error"] = "нечего конвертировать"
	return res


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0
