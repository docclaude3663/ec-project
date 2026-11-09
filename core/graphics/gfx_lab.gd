class_name GfxLab extends RefCounted

#####################################
## GfxLab. Корректор графики: чистый дефолт Godot и запись отличий (ATTN_14 §14.16)
#####################################
## Нужен, чтобы смотреть влияние каждого параметра графики на экране «как в Godot по умолчанию», а не поверх Look, Time и Quality.
## Вход: карточка Lab (Observe, Look, только debug) или кнопка во вкладке Lab (F3). Выход: любая карточка Look, Time
## или Quality, а также выход из Observe. Пока Lab включён, GraphicsManager ничего не применяет сам (lab_mode), поэтому
## правки из Remote или из вкладки Lab никто не перезапишет.
##
## Что делает вход:
##  - Environment заменяется новым Environment.new() (умолчания движка), camera_attributes сбрасывается;
##  - свет окружения (Sun, SkyFill, TableLamp, RoomProbe) получает умолчания своего класса, поза (угол, положение) остаётся;
##    у лампы остаются дальность и угол конуса, у пробы размер: без них они бесполезны;
##  - камера (та, что активна при входе): fov, near, far, projection и т.д. по умолчанию. Положение, зум и cull_mask остаются;
##  - Viewport (MSAA, FXAA, TAA, атласы теней и т.д.) и настройки RenderingServer (мягкие тени, SSAO quality): умолчания движка;
##  - слой миниатюры (tilt-shift, виньетка) обнулён и скрыт.
## Комната, мебель, дорога, их материалы и цвета не трогаются.
##
## Птички (FLAGS) включают поверх чистого дефолта то, что обычно делает картинку «не дефолтной»: фейковый AO, SkyFill, лампы,
## пробу отражений и т.д. Их состояние запоминается в Settings [lab] и применяется при каждом входе в Lab.
##
## Слепок: сразу после сброса снимаются значения всех свойств целей. diff() сравнивает текущие значения со слепком,
## поэтому правку можно делать где угодно (Remote, вкладка Lab) и записать одной кнопкой: Lab узнаёт об изменениях сравнением.
## Файл: JSON с отличиями от дефолта (значения строками var_to_str), user://lab/<имя>.json, копия в проект res://data/graphics/lab/.
## Из свойств Node3D в слепок не входят transform и visible: видимость задают только птички.

## ⚡Птичка изменилась или применилась
signal flags_changed
## ⚡Lab включён, выключен, сброшен заново, загружен файл
signal state_changed

const DIR_USER := "user://lab/"
const DIR_PROJECT := "res://data/graphics/lab/"
const SETTINGS_SECTION := "lab"
const FLAGS_KEY := "flags"
const FORMAT := 1

## Птичка = что включено поверх дефолта. Порядок = порядок во вкладке
const FLAGS := [
	{"id": "sun", "title": "Солнце (Sun)", "default": true,
			"tip": "Направленный свет с умолчаниями Godot (энергия 1, тени выкл). Угол берётся от текущего Time. Выкл: только ambient"},
	{"id": "sky_fill", "title": "SkyFill (заливка «небо»)", "default": false,
			"tip": "Второй направленный свет, умолчания Godot. Фейк объёма: рассеянный свет окна"},
	{"id": "lamp", "title": "Лампа над столом (TableLamp)", "default": false,
			"tip": "SpotLight над столом, умолчания Godot (энергия 1, дальность и угол конуса сохранены). Энергию поднимайте сами"},
	{"id": "room_lights", "title": "Лампы комнаты (из сцены)", "default": false,
			"tip": "Узел Lights комнаты. Энергия и тени такие, как заданы в сцене комнаты"},
	{"id": "probe", "title": "ReflectionProbe", "default": false,
			"tip": "Статичная проба отражений над столом (пластиковый блик)"},
	{"id": "fake_ao", "title": "Ложный AO (FakeAO)", "default": false,
			"tip": "Тёмные градиентные квады у стыков стен и пола"},
	{"id": "shell_shadows", "title": "Тень от стен, рамы, штор и потолка", "default": false,
			"tip": "Трюк Observe: оболочка комнаты отбрасывает тень (рисунок окна на столе). Выкл: стены тени не отбрасывают"},
	{"id": "track_shadows", "title": "Тени траков", "default": false,
			"tip": "Траки отбрасывают тень (выбор игрока, в Lab не пишется в settings.cfg)"},
	{"id": "miniature", "title": "Слой tilt-shift и виньетки", "default": false,
			"tip": "Показывает полноэкранный слой миниатюры. Сила и виньетка обнулены: поднимайте strength и vignette в материале GFX/MiniatureLayer"},
	{"id": "dof", "title": "CameraAttributes (DOF, экспозиция)", "default": false,
			"tip": "Подключает пустой CameraAttributesPractical к WorldEnvironment. DOF и экспозиция выключены, включайте сами"},
]

## Порядок целей в файле и в списке отличий
const TARGETS := ["env", "sun", "sky_fill", "lamp", "probe", "camera", "viewport", "rs", "mini", "dof"]
## Цели-узлы света: ключи словаря контекста
const NODE_TARGETS := ["sun", "sky_fill", "lamp", "probe"]
## Что остаётся при сбросе узла (по сути поза и габарит, не «картинка»)
const KEEP := {
	"lamp": ["spot_range", "spot_angle"],
	"probe": ["size", "origin_offset"],
}
## Свойства, которые Lab не сбрасывает и не пишет: физические единицы света пересчитывают энергию, а editor_only на картинку не влияет
const CHAIN_SKIP := ["light_temperature", "light_intensity_lumens", "light_intensity_lux", "editor_only"]
## Классы, на которых цепочка наследования обрывается (их свойства: поза, имя, слои)
const CHAIN_STOP := ["Node3D", "VisualInstance3D", "Node", "Resource", "RefCounted", "Object"]
## Типы значений, которые попадают в слепок и в файл
const DIFF_TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_STRING]

const CAMERA_PROPS := ["projection", "fov", "size", "near", "far", "keep_aspect", "h_offset", "v_offset", "frustum_offset", "doppler_tracking"]
const VIEWPORT_PROPS := ["msaa_3d", "screen_space_aa", "use_taa", "use_debanding", "use_occlusion_culling", "mesh_lod_threshold",
		"positional_shadow_atlas_size", "positional_shadow_atlas_16_bits", "scaling_3d_mode", "scaling_3d_scale",
		"texture_mipmap_bias", "fsr_sharpness", "anisotropic_filtering_level"]
## Свойство Viewport -> настройка проекта, из которой берётся умолчание движка (property_get_revert). Нет в таблице: умолчание класса SubViewport
const VIEWPORT_SETTINGS := {
	"msaa_3d": "rendering/anti_aliasing/quality/msaa_3d",
	"screen_space_aa": "rendering/anti_aliasing/quality/screen_space_aa",
	"use_taa": "rendering/anti_aliasing/quality/use_taa",
	"use_debanding": "rendering/anti_aliasing/quality/use_debanding",
	"use_occlusion_culling": "rendering/occlusion_culling/use_occlusion_culling",
	"mesh_lod_threshold": "rendering/mesh_lod/lod_change/threshold_pixels",
	"positional_shadow_atlas_size": "rendering/lights_and_shadows/positional_shadow/atlas_size",
	"positional_shadow_atlas_16_bits": "rendering/lights_and_shadows/positional_shadow/atlas_16_bits",
	"scaling_3d_mode": "rendering/scaling_3d/mode",
	"scaling_3d_scale": "rendering/scaling_3d/scale",
	"texture_mipmap_bias": "rendering/textures/default_filters/texture_mipmap_bias",
	"fsr_sharpness": "rendering/scaling_3d/fsr_sharpness",
	"anisotropic_filtering_level": "rendering/textures/default_filters/anisotropic_filtering_level",
}
## Параметры шейдера миниатюры (GraphicsManager.MINI_SHADER) и их значения при сбросе: сила и виньетка по нулям
const MINI_DEFAULTS := {
	"strength": 0.0, "pitch_scale": 1.0, "focus_y": 0.55, "band": 0.16, "falloff": 0.32, "max_lod": 3.5, "vignette": 0.0,
}

## Включён ли Lab
var active := false
## Причина последней неудачи (запись, чтение, загрузка)
var last_error := ""
## Замечания последней загрузки файла (неизвестные цели и свойства)
var last_warnings: Array[String] = []

var _ctx: Dictionary = {}
var _flags: Dictionary = {}     # id -> bool, запоминаются в Settings
var _targets: Dictionary = {}   # имя цели -> {"obj": Object, "props": Array}
var _base: Dictionary = {}      # имя цели -> {свойство: значение после сброса}
var _saved: Dictionary = {}     # состояние до входа в Lab (вернуть при выходе)
var _lab_attr: CameraAttributesPractical
var _rs: RenderSettings
var _camera: Camera3D


## Настройки RenderingServer, которые не лежат ни в какой ноде: тени и SSAO quality. Правятся только из вкладки Lab
class RenderSettings extends RefCounted:
	## Свойство -> [настройка проекта, запасное значение]
	const MAP := {
		"dir_shadow_atlas_size": ["rendering/lights_and_shadows/directional_shadow/size", 4096],
		"dir_shadow_atlas_16_bits": ["rendering/lights_and_shadows/directional_shadow/16_bits", true],
		"dir_soft_shadow_quality": ["rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2],
		"pos_soft_shadow_quality": ["rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2],
		"ssao_quality": ["rendering/environment/ssao/quality", 2],
		"ssao_half_size": ["rendering/environment/ssao/half_size", true],
		"ssao_adaptive_target": ["rendering/environment/ssao/adaptive_target", 0.5],
		"ssao_blur_passes": ["rendering/environment/ssao/blur_passes", 2],
		"ssao_fadeout_from": ["rendering/environment/ssao/fadeout_from", 50.0],
		"ssao_fadeout_to": ["rendering/environment/ssao/fadeout_to", 300.0],
	}
	var dir_shadow_atlas_size := 4096
	var dir_shadow_atlas_16_bits := true
	var dir_soft_shadow_quality := 2
	var pos_soft_shadow_quality := 2
	var ssao_quality := 2
	var ssao_half_size := true
	var ssao_adaptive_target := 0.5
	var ssao_blur_passes := 2
	var ssao_fadeout_from := 50.0
	var ssao_fadeout_to := 300.0

	## Умолчания движка: property_get_revert, а если настройки нет, запасное значение из таблицы
	func load_defaults() -> void:
		for k in MAP:
			var entry: Array = MAP[k]
			var v: Variant = entry[1]
			var d: Variant = ProjectSettings.property_get_revert(String(entry[0]))
			if d != null and typeof(d) == typeof(v):
				v = d
			set(k, v)

	func apply() -> void:
		RenderingServer.directional_shadow_atlas_set_size(dir_shadow_atlas_size, dir_shadow_atlas_16_bits)
		RenderingServer.directional_soft_shadow_filter_set_quality(dir_soft_shadow_quality as RenderingServer.ShadowQuality)
		RenderingServer.positional_soft_shadow_filter_set_quality(pos_soft_shadow_quality as RenderingServer.ShadowQuality)
		RenderingServer.environment_set_ssao_quality(ssao_quality as RenderingServer.EnvironmentSSAOQuality,
				ssao_half_size, ssao_adaptive_target, ssao_blur_passes, ssao_fadeout_from, ssao_fadeout_to)


func _init() -> void:
	var saved: Variant = Settings.get_value(SETTINGS_SECTION, FLAGS_KEY, null)
	for f in FLAGS:
		var v: bool = f["default"]
		if saved is Dictionary and (saved as Dictionary).has(f["id"]):
			v = bool((saved as Dictionary)[f["id"]])
		_flags[f["id"]] = v


# ==========================================
# ВХОД, ВЫХОД, ПТИЧКИ
# ==========================================

## Включить Lab. ctx собирает GraphicsManager: world_env, sun, sky_fill, lamp, probe, mini_rect, mini_mat, viewport,
## track_get, track_set, observe_active
func enter(ctx: Dictionary) -> void:
	if active:
		return
	_ctx = ctx
	_save_state()
	active = true
	_rebuild()
	state_changed.emit()


## Чистый дефолт заново (птички остаются как есть, правки теряются)
func rebuild() -> void:
	if not active:
		return
	_rebuild()
	state_changed.emit()


## Выключить Lab и вернуть всё, что было до входа. Дальше GraphicsManager применяет Look, Time и Quality
func leave() -> void:
	if not active:
		return
	active = false
	var we := _ctx["world_env"] as WorldEnvironment
	we.environment = _saved["env"]
	we.camera_attributes = _saved["attrs"]
	for t in NODE_TARGETS:
		var n := _ctx.get(t) as Node3D
		if is_instance_valid(n) and _saved.has(t):
			_restore(n, _saved[t])
	if is_instance_valid(_camera) and _saved.has("camera"):
		_restore(_camera, _saved["camera"])
	_restore(_ctx["viewport"] as Viewport, _saved["viewport"])
	(_ctx["mini_rect"] as CanvasItem).visible = bool(_saved.get("mini_visible", false))
	(_ctx["track_set"] as Callable).call(int(_saved["track"]))
	var rb := _room()
	if rb != null:
		var lights: Variant = rb.call("get_room_lights")
		if lights is Node3D:
			(lights as Node3D).visible = true
		var ao := _fake_ao()
		if ao != null:
			ao.visible = true
		rb.call("apply_observe_shadows", bool((_ctx["observe_active"] as Callable).call()))
	_targets.clear()
	_base.clear()
	_lab_attr = null
	_rs = null
	_camera = null
	_saved.clear()
	state_changed.emit()


func get_flag(id: String) -> bool:
	return bool(_flags.get(id, false))


## Птичка запоминается в settings.cfg. Включённый Lab применяет её сразу
## persist = false: только на время работы (загрузка файла не должна менять запомненные птички)
func set_flag(id: String, on: bool, persist := true) -> void:
	if not _flags.has(id) or bool(_flags[id]) == on:
		return
	_flags[id] = on
	if persist:
		Settings.set_value(SETTINGS_SECTION, FLAGS_KEY, _flags.duplicate())
	if active:
		_apply_flag(id, on)
	flags_changed.emit()


## Настройки RenderingServer (тени, SSAO quality): нет в Remote, правятся из вкладки Lab. null: Lab выключен
func rs_get(prop: String) -> Variant:
	return _rs.get(prop) if _rs != null else null


func rs_set(prop: String, value: Variant) -> void:
	if _rs == null or not RenderSettings.MAP.has(prop):
		return
	_rs.set(prop, value)
	_rs.apply()


## Все птички к значениям по умолчанию (чистый дефолт Godot)
func reset_flags() -> void:
	for f in FLAGS:
		set_flag(f["id"], f["default"])


## Комнату пересобрали или заменили: новые узлы получают птички заново (зовёт RoomBuilder)
func apply_room_flags() -> void:
	if not active:
		return
	for id in ["room_lights", "fake_ao", "shell_shadows"]:
		_apply_flag(id, bool(_flags[id]))


# ==========================================
# СЛЕПОК И ОТЛИЧИЯ
# ==========================================

## Отличия от слепка: {цель: {свойство: значение}}. Пустые цели не входят
func diff() -> Dictionary:
	var out := {}
	for t in TARGETS:
		if not _targets.has(t):
			continue
		var obj: Object = _targets[t]["obj"]
		var base: Dictionary = _base.get(t, {})
		var changed := {}
		for p in _targets[t]["props"]:
			var cur: Variant = _read_prop(obj, p)
			if not _same(base.get(p), cur):
				changed[p] = cur
		if not changed.is_empty():
			out[t] = changed
	return out


func changed_count() -> int:
	var n := 0
	var d := diff()
	for t in d:
		n += (d[t] as Dictionary).size()
	return n


## Список отличий для показа: «цель.свойство: было -> стало»
func changes_text(max_lines := 40) -> String:
	var lines := PackedStringArray()
	var d := diff()
	for t in TARGETS:
		if not d.has(t):
			continue
		var base: Dictionary = _base.get(t, {})
		var ch: Dictionary = d[t]
		for k in ch:
			lines.append("%s.%s: %s -> %s" % [t, k, _fmt(base.get(k)), _fmt(ch[k])])
	var total := lines.size()
	if total > max_lines:
		lines = lines.slice(0, max_lines)
		lines.append("... ещё %d" % (total - max_lines))
	return "\n".join(lines)


# ==========================================
# ФАЙЛЫ
# ==========================================

## Записать отличия в user://lab/<имя>.json. Возвращает путь или "" (причина в last_error)
func save_file(file_name: String, note := "") -> String:
	last_error = ""
	if not active:
		last_error = "Lab выключен: записывать нечего"
		return ""
	var fname := file_name.strip_edges().validate_filename()
	if fname.is_empty():
		fname = "lab_" + Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var flags := {}
	for f in FLAGS:
		if bool(_flags[f["id"]]) != bool(f["default"]):
			flags[f["id"]] = bool(_flags[f["id"]])
	var data := {
		"format": FORMAT,
		"engine": str(Engine.get_version_info().get("string", "")),
		"created": Time.get_datetime_string_from_system(false, true),
		"room": _room_id(),
		"base": "godot_default",
		"note": note,
		"flags": flags,
	}
	var d := diff()
	for t in d:
		var strs := {}
		for k in (d[t] as Dictionary):
			strs[k] = var_to_str(d[t][k])
		data[t] = strs
	DirAccess.make_dir_recursive_absolute(DIR_USER)
	var path := DIR_USER + fname + ".json"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		last_error = "Не открыт файл %s (код %d)" % [path, FileAccess.get_open_error()]
		return ""
	fh.store_string(JSON.stringify(data, "\t", true) + "\n")
	fh.close()
	return path


## Файлы экспериментов: [{path, title, project}] (сначала user://, затем проект)
func list_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in [DIR_USER, DIR_PROJECT]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f in files:
			var fs := String(f)
			if not fs.ends_with(".json"):
				continue
			var is_project: bool = dir == DIR_PROJECT
			out.append({"path": dir + fs, "title": fs.get_basename() + (" [проект]" if is_project else ""), "project": is_project})
	return out


## Загрузить файл: чистый дефолт, птички и значения из файла. Неизвестное пропускается (last_warnings)
func load_file(path: String) -> bool:
	last_error = ""
	last_warnings.clear()
	if not active:
		last_error = "Lab выключен"
		return false
	if not FileAccess.file_exists(path):
		last_error = "Нет файла " + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		last_error = "Файл не разобран как JSON-объект: " + path
		return false
	var data: Dictionary = parsed
	_rebuild()
	var fl := {}
	if data.get("flags") is Dictionary:
		fl = data["flags"]
	for f in FLAGS:
		set_flag(f["id"], bool(fl.get(f["id"], f["default"])), false)
	for t in TARGETS:
		if not data.has(t):
			continue
		if not (data[t] is Dictionary):
			last_warnings.append("%s: не объект" % t)
			continue
		if not _targets.has(t):
			last_warnings.append("нет цели %s (птичка или объект недоступны)" % t)
			continue
		var obj: Object = _targets[t]["obj"]
		var props: Array = _targets[t]["props"]
		for k in (data[t] as Dictionary):
			if not props.has(k):
				last_warnings.append("%s.%s: свойства нет в этой версии" % [t, k])
				continue
			var raw := String(data[t][k])
			if raw.begins_with("Object("):
				last_warnings.append("%s.%s: объекты из файла не читаются" % [t, k])
				continue
			var v: Variant = str_to_var(raw)
			var cur: Variant = _read_prop(obj, k)
			v = _coerce(v, cur)
			if v == null or typeof(v) == TYPE_OBJECT:
				last_warnings.append("%s.%s: значение не прочитано" % [t, k])
				continue
			_write_prop(obj, k, v)
		if t == "rs":
			_rs.apply()
	state_changed.emit()
	return true


## Удалить файл (только из user://lab/: файлы проекта удаляются руками)
func delete_file(path: String) -> bool:
	last_error = ""
	if not path.begins_with(DIR_USER):
		last_error = "Удаляются только файлы из user://lab/"
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		last_error = "Не удалён %s (код %d)" % [path, err]
		return false
	return true


## Скопировать файл в res://data/graphics/lab/ (только при запуске из редактора, там res:// пишется)
func copy_to_project(path: String) -> String:
	last_error = ""
	if not OS.has_feature("editor"):
		last_error = "В проект можно копировать только при запуске из редактора"
		return ""
	if not FileAccess.file_exists(path):
		last_error = "Нет файла " + path
		return ""
	DirAccess.make_dir_recursive_absolute(DIR_PROJECT)
	var dst := DIR_PROJECT + path.get_file()
	var fh := FileAccess.open(dst, FileAccess.WRITE)
	if fh == null:
		last_error = "Не открыт файл %s (код %d)" % [dst, FileAccess.get_open_error()]
		return ""
	fh.store_string(FileAccess.get_file_as_string(path))
	fh.close()
	return dst


# ==========================================
# СБРОС
# ==========================================

func _rebuild() -> void:
	_targets.clear()
	_base.clear()
	_reset_objects()
	_build_targets()
	_apply_flags()


## Состояние до входа: Environment, атрибуты камеры, свет, камера, Viewport, слой миниатюры, тени траков
func _save_state() -> void:
	_saved.clear()
	var we := _ctx["world_env"] as WorldEnvironment
	_saved["env"] = we.environment
	_saved["attrs"] = we.camera_attributes
	for t in NODE_TARGETS:
		var n := _ctx.get(t) as Node3D
		if is_instance_valid(n):
			_saved[t] = _capture_node(n)
	var vp := _ctx["viewport"] as Viewport
	_camera = vp.get_camera_3d()
	if _camera != null:
		var cd := _capture(_camera, _existing(_camera, CAMERA_PROPS))
		cd["environment"] = _camera.environment
		cd["attributes"] = _camera.attributes
		_saved["camera"] = cd
	_saved["viewport"] = _capture(vp, _existing(vp, VIEWPORT_PROPS))
	_saved["mini_visible"] = (_ctx["mini_rect"] as CanvasItem).visible
	_saved["track"] = (_ctx["track_get"] as Callable).call()


func _reset_objects() -> void:
	var we := _ctx["world_env"] as WorldEnvironment
	we.environment = Environment.new()
	we.camera_attributes = null
	_lab_attr = null
	for t in NODE_TARGETS:
		var n := _ctx.get(t) as Node3D
		if is_instance_valid(n):
			_reset_node(n, KEEP.get(t, []))
	if is_instance_valid(_camera):
		_reset_camera(_camera)
	_reset_viewport(_ctx["viewport"] as Viewport)
	_rs = RenderSettings.new()
	_rs.load_defaults()
	_rs.apply()
	var mat := _ctx.get("mini_mat") as ShaderMaterial
	if mat != null:
		for k in MINI_DEFAULTS:
			mat.set_shader_parameter(k, MINI_DEFAULTS[k])


## Свойства узла берутся с нового экземпляра того же класса (умолчания Godot). Поза не трогается
func _reset_node(n: Node3D, keep: Array) -> void:
	var fresh: Object = ClassDB.instantiate(n.get_class())
	if fresh == null:
		return
	for p in _chain_props(n):
		var nm: String = p["name"]
		if keep.has(nm):
			continue
		n.set(nm, fresh.get(nm))
	fresh.free()


func _reset_camera(c: Camera3D) -> void:
	var fresh := Camera3D.new()
	for nm in _existing(c, CAMERA_PROPS):
		c.set(nm, fresh.get(nm))
	c.environment = null
	c.attributes = null
	fresh.free()


func _reset_viewport(vp: Viewport) -> void:
	var fresh := SubViewport.new()
	for nm in _existing(vp, VIEWPORT_PROPS):
		var v: Variant = fresh.get(nm)
		var setting: String = VIEWPORT_SETTINGS.get(nm, "")
		if setting != "":
			var d: Variant = ProjectSettings.property_get_revert(setting)
			if d != null and typeof(d) == typeof(v):
				v = d
		vp.set(nm, v)
	fresh.free()


func _build_targets() -> void:
	var we := _ctx["world_env"] as WorldEnvironment
	_register("env", we.environment, _stored_names(we.environment))
	for t in NODE_TARGETS:
		var n := _ctx.get(t) as Node3D
		if is_instance_valid(n):
			_register(t, n, _stored_names(n))
	if is_instance_valid(_camera):
		_register("camera", _camera, _existing(_camera, CAMERA_PROPS))
	var vp := _ctx["viewport"] as Viewport
	_register("viewport", vp, _existing(vp, VIEWPORT_PROPS))
	_register("rs", _rs, RenderSettings.MAP.keys())
	var mat := _ctx.get("mini_mat") as ShaderMaterial
	if mat != null:
		_register("mini", mat, MINI_DEFAULTS.keys())


func _register(target: String, obj: Object, props: Array) -> void:
	_targets[target] = {"obj": obj, "props": props}
	var b := {}
	for p in props:
		b[p] = _read_prop(obj, p)
	_base[target] = b


# ==========================================
# ПТИЧКИ: применение
# ==========================================

func _apply_flags() -> void:
	for f in FLAGS:
		_apply_flag(f["id"], bool(_flags[f["id"]]))


func _apply_flag(id: String, on: bool) -> void:
	match id:
		"sun", "sky_fill", "lamp", "probe":
			var n: Variant = _ctx.get(id)
			if is_instance_valid(n) and n is Node3D:
				(n as Node3D).visible = on
		"room_lights":
			var rb := _room()
			if rb != null:
				var lights: Variant = rb.call("get_room_lights")
				if lights is Node3D:
					(lights as Node3D).visible = on
		"fake_ao":
			var ao := _fake_ao()
			if ao != null:
				ao.visible = on
		"shell_shadows":
			var rb2 := _room()
			if rb2 != null:
				rb2.call("set_shell_shadows", on)
		"track_shadows":
			(_ctx["track_set"] as Callable).call(1 if on else 0)
		"miniature":
			(_ctx["mini_rect"] as CanvasItem).visible = on
		"dof":
			_set_dof(on)


## Подключает пустой CameraAttributesPractical: DOF и экспозиция выключены. Цель dof появляется в слепке, пока птичка включена
func _set_dof(on: bool) -> void:
	var we := _ctx["world_env"] as WorldEnvironment
	if on:
		if _lab_attr == null:
			_lab_attr = CameraAttributesPractical.new()
		we.camera_attributes = _lab_attr
		if not _targets.has("dof"):
			_register("dof", _lab_attr, _stored_names(_lab_attr))
	else:
		we.camera_attributes = null
		_lab_attr = null
		_targets.erase("dof")
		_base.erase("dof")


# ==========================================
# ВНУТРЕННЕЕ
# ==========================================

func _room() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(&"room_root") if tree else null


func _room_id() -> String:
	var rb := _room()
	if rb != null:
		return String(rb.call("get_room_id"))
	return ""


func _fake_ao() -> Node3D:
	var rb := _room()
	if rb == null:
		return null
	var vis: Variant = rb.get("visuals")
	if vis is Node and is_instance_valid(vis):
		return (vis as Node).find_child("FakeAO", true, false) as Node3D
	return null


## Хранимые свойства класса объекта и его предков до Node3D / Resource, без служебных
static func _chain_props(obj: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cls := String(obj.get_class())
	while cls != "" and not CHAIN_STOP.has(cls):
		for p in ClassDB.class_get_property_list(cls, true):
			if (int(p["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or int(p["type"]) == TYPE_NIL:
				continue
			if CHAIN_SKIP.has(String(p["name"])):
				continue
			out.append(p)
		cls = String(ClassDB.get_parent_class(cls))
	return out


## Имена свойств простых типов (в слепок)
static func _stored_names(obj: Object) -> Array:
	var out := []
	for p in _chain_props(obj):
		if DIFF_TYPES.has(int(p["type"])):
			out.append(String(p["name"]))
	return out


## Из names оставляет те, что есть у объекта (имена свойств движка меняются между версиями)
static func _existing(obj: Object, names: Array) -> Array:
	var have := {}
	for p in obj.get_property_list():
		have[String(p["name"])] = true
	var out := []
	for n in names:
		if have.has(n):
			out.append(n)
	return out


static func _capture(obj: Object, props: Array) -> Dictionary:
	var d := {}
	for p in props:
		d[p] = obj.get(p)
	return d


static func _capture_node(n: Node3D) -> Dictionary:
	var d := {"visible": n.visible}
	for p in _chain_props(n):
		d[p["name"]] = n.get(p["name"])
	return d


static func _restore(obj: Object, d: Dictionary) -> void:
	for k in d:
		obj.set(k, d[k])


static func _read_prop(obj: Object, prop: String) -> Variant:
	if obj is ShaderMaterial:
		return (obj as ShaderMaterial).get_shader_parameter(prop)
	return obj.get(prop)


static func _write_prop(obj: Object, prop: String, v: Variant) -> void:
	if obj is ShaderMaterial:
		(obj as ShaderMaterial).set_shader_parameter(prop, v)
	else:
		obj.set(prop, v)


## Значение из файла приводится к типу текущего: int и float между собой. Несовпадение типов даёт null
static func _coerce(v: Variant, cur: Variant) -> Variant:
	if typeof(v) == typeof(cur):
		return v
	if typeof(cur) == TYPE_FLOAT and typeof(v) == TYPE_INT:
		return float(v)
	if typeof(cur) == TYPE_INT and typeof(v) == TYPE_FLOAT:
		return int(v)
	return null


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b)
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b)
		TYPE_VECTOR4:
			return (a as Vector4).is_equal_approx(b)
	return a == b


static func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return String.num(v, 4)
	return var_to_str(v)
