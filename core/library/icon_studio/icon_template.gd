extends Resource

########################
## Icon Studio: шаблон съёмки (ATTN_18 §18.3.3)
########################
## Всё, что не зависит от размера объекта: углы, проекция, свет, фон, качество, коррекция, размер.
## Размер объекта (дистанция камеры, size орто) вычисляется кнопкой Fit по AABB.
## Пока шаблон один, рабочий, хранится в user://icon_studio.cfg (to_dict / from_dict).
## Именованные шаблоны: встроенные (icon_templates.gd) и свои в user://icon_studio/templates/*.tres (шаг I6).

const SLOT_COUNT := 6

@export var id: StringName = &"default"
@export var title := "По умолчанию"
@export var output_size := Vector2i(150, 150)
## Поле вокруг объекта при Fit, доля кадра
@export_range(0.0, 0.5, 0.01) var fit_margin := 0.08
## Слоты ракурса: SLOT_COUNT элементов, Dictionary (capture_slot) или null
@export var slots: Array = []
@export var smooth_slots := true

@export_category("Light")
@export var light_follow_camera := true
## Углы источников относительно направления камеры, градусы
@export var key_pitch := -35.0
@export var key_yaw := 40.0
@export var fill_pitch := -10.0
@export var fill_yaw := -55.0
@export var rim_pitch := -20.0
@export var rim_yaw := 160.0
@export var key_energy := 1.25
@export var fill_energy := 0.35
@export var rim_energy := 0.6
@export var light_color := Color.WHITE
@export var shadow := true
@export var shadow_softness := 1.5
## Как рисуется тень на прозрачном фоне и на ровном цвете: 0 шейдер с light() (ATTENUATION), 1 shadow_to_opacity
@export var catcher_mode := 0

@export_category("Background")
## 0 прозрачный, 1 цвет, 2 поверхность с горизонтом
@export var bg_mode := 1
@export var bg_color := Color(0.85, 0.88, 0.92)
@export var sky_top := Color(0.55, 0.7, 0.9)
@export var sky_horizon := Color(0.85, 0.9, 0.95)
@export var ground_color := Color(0.62, 0.62, 0.6)

@export_category("Quality")
@export var quality_id: StringName = &"icon_max"
## Съёмка идёт в N раз крупнее и уменьшается (шаг I5)
@export_range(1, 8) var supersample := 4

@export_category("Post")
@export var tonemap: int = Environment.TONE_MAPPER_FILMIC
@export var exposure := 1.0
@export var brightness := 1.0
@export var contrast := 1.0
@export var saturation := 1.0
@export var sharpen := 0.0
## Обрезка по прозрачности: объект масштабируется до размера кадра минус padding (нужен прозрачный фон)
@export var trim_to_content := false
@export_range(0.0, 0.4, 0.01) var padding := 0.0

@export_category("Output")
## Какие форматы писать за одну съёмку
@export var fmt_png := true
@export var fmt_webp := false
@export var fmt_jpg := false
@export var webp_lossy := false
@export_range(0.05, 1.0, 0.01) var file_quality := 0.9
## Подстановки: {category} {tag} {name} {key} {size}
@export var name_pattern := "{category}_{name}_{size}"
## Сколько цветов оставлять в SVG-пикселях (сравнение форматов)
@export_range(2, 64) var svg_colors := 16


func _init() -> void:
	_fix_slots()


func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			d[String(p.name)] = get(p.name)
	d["slots"] = slots.duplicate(true)
	return d


func from_dict(d: Dictionary) -> void:
	for k in d:
		if k == "slots":
			slots = (d[k] as Array).duplicate(true) if d[k] is Array else []
			continue
		if not (k in self):
			continue
		var cur: Variant = get(k)
		if typeof(d[k]) == typeof(cur):
			set(k, d[k])
	_fix_slots()


func _fix_slots() -> void:
	slots.resize(SLOT_COUNT)
