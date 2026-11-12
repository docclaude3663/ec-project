class_name VariantApplier extends RefCounted

# XX claude-library (новый файл)
########################
## VariantApplier. Применение исполнения к мешам модели (ATTN_22 §22.6.3, шаги L3 и L4)
########################
## Один код для Library и игры. Красятся только переданные меши (C_Visual.mesh_nodes: кузов; тележки и колёса
## строятся позже и в список не попадают). Материал модели не меняется: на поверхность ставится override-копия.
## Идемпотентно: каждое применение заново берёт материал меша, копии не наслаиваются. Чужие override (поставленные
## не нами) сохраняются и возвращаются при сбросе. Свои копии помечены метой META.
## Контур выделения (слои видимости) и подсветка состояний (material_overlay) от override не зависят.

## Префикс имени материала красимой поверхности (0_ATTN_24 §24.4). Если у модели есть такие материалы,
## зона «Весь корпус» красит только их; без них поведение прежнее (красятся все непрозрачные)
const PAINT_PREFIX := "paint_"
const META := &"library_paint"
const META_PREV := &"library_paint_prev"


## variant: ModelVariant.to_dict() (или {} для сброса). meshes: Array[MeshInstance3D].
## overlays: имя меша -> ShaderMaterial накладки слоя кисти (PaintEngine.make_overlay или слой из сейва, C2). Накладка
## встаёт в цепочку next_pass override-копии каждой поверхности меша (своя копия накладки на поверхность)
static func apply(meshes: Array, variant: Dictionary, overlays: Dictionary = {}) -> void:
	var paint: Dictionary = {}
	var pv: Variant = variant.get("paint")
	if pv is Dictionary:
		paint = pv
	var zones := PaintData.zones(paint)
	var only_paint := has_paint_materials(meshes)
	# Слои кисти с PNG внутри исполнения (игра, сейв); живые накладки Library (параметр) главнее
	var all_overlays := PaintLayers.overlays_from(variant)
	all_overlays.merge(overlays, true)
	for mi in meshes:
		if mi is MeshInstance3D and is_instance_valid(mi):
			var ov: Variant = all_overlays.get(str(mi.name))
			_apply_mesh(mi, zones, ov as Material, only_paint)


## Снять покраску: вернуть материалы модели
static func clear(meshes: Array) -> void:
	apply(meshes, {})


## true, если у какого-нибудь меша есть поверхность с материалом paint_* (имя материала модели, не override)
static func has_paint_materials(meshes: Array) -> bool:
	for mi in meshes:
		if not (mi is MeshInstance3D) or not is_instance_valid(mi) or (mi as MeshInstance3D).mesh == null:
			continue
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			if _is_paint_material(mesh.surface_get_material(i)):
				return true
	return false


static func _is_paint_material(mat: Material) -> bool:
	return mat != null and mat.resource_name.to_lower().begins_with(PAINT_PREFIX)


static func _apply_mesh(mi: MeshInstance3D, zones: Dictionary, overlay: Material, only_paint := false) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var cur := mi.get_surface_override_material(i)
		var ours := cur != null and cur.has_meta(META)
		# Основа: материал меша; чужой override (не наш) считается основой и запоминается
		var base: Material = mesh.surface_get_material(i) if (cur == null or ours) else cur
		var prev: Variant = null
		if ours:
			# get_meta(ключ, null) при отсутствии ключа пишет ошибку (null считается «без умолчания»): сначала has_meta
			prev = cur.get_meta(META_PREV) if cur.has_meta(META_PREV) else null
			if prev != null:
				base = prev
		elif cur != null:
			prev = cur
		var spec := _spec_for(mi, i, base, zones, only_paint)
		var painted: Material = null
		if not spec.is_empty() and base is BaseMaterial3D:
			painted = _painted(base as BaseMaterial3D, spec)
		if overlay != null and base != null:
			if painted == null:
				painted = base.duplicate() as Material
				painted.set_meta(META, true)
			_insert_overlay(painted, overlay)
		if painted == null:
			if ours:
				mi.set_surface_override_material(i, prev)
			continue
		if prev != null:
			painted.set_meta(META_PREV, prev)
		mi.set_surface_override_material(i, painted)


## Накладка встаёт первой в цепочке next_pass: прежняя цепочка (контур, питание) остаётся за ней и не меняется
static func _insert_overlay(m: Material, overlay: Material) -> void:
	var ov := overlay.duplicate() as Material
	ov.next_pass = m.next_pass
	m.next_pass = ov


static func _spec_for(mi: MeshInstance3D, surface: int, base: Material, zones: Dictionary, only_paint := false) -> Dictionary:
	var id := PaintZones.zone_id(mi, surface)
	if zones.has(id):
		return zones[id]
	if only_paint and not _is_paint_material(base):
		return {}
	if zones.has(PaintData.ALL) and not PaintZones.is_transparent(base):
		return zones[PaintData.ALL]
	return {}


static func _painted(base: BaseMaterial3D, spec: Dictionary) -> BaseMaterial3D:
	var m := base.duplicate() as BaseMaterial3D
	var color := Color.from_string(str(spec.get("color", "#ffffff")), Color.WHITE)
	if bool(spec.get("cover", true)):
		# Кроющая: рисунок модели (текстура, цвет вершин) закрыт, цвет плоский, нормали и геометрия остаются
		m.albedo_texture = null
		m.vertex_color_use_as_albedo = false
		color.a = base.albedo_color.a
		m.albedo_color = color
	else:
		# Лессировка: цвет умножается на рисунок модели
		m.albedo_color = Color(base.albedo_color.r * color.r, base.albedo_color.g * color.g, base.albedo_color.b * color.b, base.albedo_color.a)
	var finish := str(spec.get("finish", "keep"))
	if finish != "keep" and PaintData.FINISHES.has(finish):
		var f: Dictionary = PaintData.FINISHES[finish]
		m.roughness = float(f["rough"])
		m.metallic = float(f["metal"])
		if m is StandardMaterial3D and bool(spec.get("cover", true)):
			m.roughness_texture = null
			m.metallic_texture = null
	m.set_meta(META, true)
	return m
