extends Node

# XX claude-library (новый файл)
## Проверка шагов L3 и L4 (ATTN_22): данные покраски (PaintData), зоны (PaintZones), применение к мешам
## (VariantApplier) и исполнение в сущности (Entity.variant, C_Visual, сейв).
## Запуск: открыть tests/library_paint_test.tscn и нажать F6.
## Итог в Output: строки PASS/FAIL и «Library paint: n/m».
## Блок про сущность берёт объект train.boxcar.wagon_02 из каталога; если его переименуют, поправить KEY.

const KEY := &"train.boxcar.wagon_02"

var _ok := 0
var _all := 0


func _ready() -> void:
	_test_paint_data()
	_test_zones()
	_test_applier()
	await _test_entity()
	print("Library paint: %d/%d" % [_ok, _all])
	get_tree().quit(0 if _ok == _all else 1)


# --- помощники ---

func _std(color: Color, with_texture := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	if with_texture:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		m.albedo_texture = ImageTexture.create_from_image(img)
	return m


## MeshInstance3D с одной поверхностью-коробкой на каждый материал (null допустим)
func _mesh_node(node_name: String, materials: Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for i in materials.size():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
		mesh.surface_set_material(i, materials[i])
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi


func _paint(zones: Dictionary) -> Dictionary:
	var p := PaintData.new_paint()
	for id in zones:
		var z: Array = zones[id]
		PaintData.set_zone(p, id, Color.from_string(z[0], Color.WHITE), z[1], z[2])
	return {"paint": p}


# --- PaintData ---

func _test_paint_data() -> void:
	var p := PaintData.new_paint()
	_check("новая покраска: версия 2, слоёв нет, пусто", int(p["v"]) == 2 and (p["layers"] as Array).is_empty() and PaintData.is_empty(p))
	PaintData.set_zone(p, "all", Color.from_string("#c0392b", Color.WHITE))
	var spec := PaintData.zone_spec(p, "all")
	_check("set_zone создаёт грунт и зону", PaintData.base_layer(p).get("id") == "base" and spec["color"] == "#c0392b"
		and spec["finish"] == "keep" and spec["cover"] == true and not PaintData.is_empty(p))
	PaintData.set_zone(p, "Body#1", Color.WHITE, "gloss", false)
	var spec2 := PaintData.zone_spec(p, "Body#1")
	_check("отделка и лессировка записываются", spec2["finish"] == "gloss" and spec2["cover"] == false)
	PaintData.set_zone(p, "Body#2", Color.WHITE, "нет_такой_отделки")
	_check("неизвестная отделка заменяется на keep", PaintData.zone_spec(p, "Body#2")["finish"] == "keep")
	PaintData.clear_zone(p, "Body#1")
	_check("clear_zone убирает зону, остальные на месте", PaintData.zone_spec(p, "Body#1").is_empty() and not PaintData.zone_spec(p, "all").is_empty())
	PaintData.clear_all(p)
	_check("clear_all убирает все зоны, грунт остаётся", PaintData.is_empty(p) and not PaintData.base_layer(p).is_empty())
	var old := {"layers": [{"id": "base", "zones": {"all": "#112233", "x": 5, "y": {"finish": "gloss"}}}]}
	var z := PaintData.zones(old)
	_check("старая форма (строка) читается, мусор пропускается", z.size() == 1 and z["all"]["color"] == "#112233" and z["all"]["cover"] == true)
	var hidden := {"layers": [{"id": "base", "visible": false, "zones": {"all": "#112233"}}]}
	_check("скрытый слой даёт пусто", PaintData.zones(hidden).is_empty())
	_check("мусор вместо слоёв не роняет", PaintData.zones({"layers": 5}).is_empty() and PaintData.zones({}).is_empty())
	var v := ModelVariant.new()
	v.id = "t1"
	PaintData.set_zone(v.paint, "Body#0", Color.from_string("#336699", Color.WHITE), "satin", false)
	var back := ModelVariant.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	var s2 := PaintData.zone_spec(back.paint, "Body#0")
	_check("покраска переживает JSON", s2["color"] == "#336699" and s2["finish"] == "satin" and s2["cover"] == false)


# --- PaintZones ---

func _test_zones() -> void:
	var glass := _std(Color(1, 1, 1, 0.3), false)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var named := _std(Color.GRAY, false)
	named.resource_name = "Краска корпуса"
	var mi := _mesh_node("Body", [_std(Color.GRAY), glass, named, null])
	(mi.mesh as ArrayMesh).surface_set_name(0, "Борт")
	var zones := PaintZones.list([mi])
	_check("зон на одну больше, чем поверхностей: «Весь корпус» первой", zones.size() == 5 and zones[0]["id"] == "all" and zones[0]["title"] == "Весь корпус")
	_check("id зоны: имя меша и номер поверхности", zones[1]["id"] == "Body#0" and zones[4]["id"] == "Body#3")
	_check("название: имя поверхности, имя материала, запасное", zones[1]["title"] == "Борт" and zones[3]["title"] == "Краска корпуса" and zones[4]["title"] == "Поверхность 4")
	_check("стекло помечено прозрачным", zones[2]["transparent"] == true and zones[1]["transparent"] == false)
	var info := ModelInfo.new()
	info.zone_titles = {"Body#1": "Окна"}
	_check("название из паспорта главнее", PaintZones.list([mi], info)[2]["title"] == "Окна")
	var mi2 := _mesh_node("Roof", [_std(Color.RED)])
	var two := PaintZones.list([mi, mi2])
	_check("у модели с несколькими мешами названия с именем меша", two.size() == 6 and str(two[5]["title"]).begins_with("Roof:"))
	_check("PaintZones.list без мешей: только «Весь корпус»", PaintZones.list([]).size() == 1)
	mi.free()
	mi2.free()


# --- VariantApplier ---

func _test_applier() -> void:
	var base := _std(Color(0.2, 0.4, 0.6, 1.0))
	var glass := _std(Color(1, 1, 1, 0.3), false)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := _mesh_node("Body", [base, glass])
	var mesh := mi.mesh as ArrayMesh

	VariantApplier.apply([mi], _paint({"all": ["#c0392b", "gloss", true]}))
	var o := mi.get_surface_override_material(0) as StandardMaterial3D
	_check("«Весь корпус»: поверхность 0 перекрашена копией с метой",
		o != null and o != base and o.has_meta(VariantApplier.META) and o.albedo_color.to_html(false) == "c0392b")
	_check("кроющая краска убрала текстуру, глянец выставил шероховатость", o.albedo_texture == null and is_equal_approx(o.roughness, 0.2))
	_check("материал модели не изменён", mesh.surface_get_material(0) == base and base.albedo_texture != null
		and base.albedo_color.is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)) and is_equal_approx(base.roughness, 0.5))
	_check("«Весь корпус» не красит прозрачную поверхность (стекло)", mi.get_surface_override_material(1) == null)

	VariantApplier.apply([mi], _paint({"all": ["#c0392b", "gloss", true]}))
	var o2 := mi.get_surface_override_material(0) as StandardMaterial3D
	_check("повторное применение не наслаивает копии", o2 != null and o2.next_pass == null
		and o2.albedo_color.to_html(false) == "c0392b" and mesh.surface_get_material(0) == base)

	VariantApplier.apply([mi], _paint({"all": ["#ffffff", "keep", true], "Body#0": ["#00ff00", "keep", true], "Body#1": ["#0000ff", "keep", true]}))
	_check("зона поверхности главнее «Весь корпус»", (mi.get_surface_override_material(0) as StandardMaterial3D).albedo_color.to_html(false) == "00ff00")
	_check("явная зона красит и стекло", mi.get_surface_override_material(1) != null)

	VariantApplier.apply([mi], _paint({"all": ["#808080", "keep", false]}))
	var tint := mi.get_surface_override_material(0) as StandardMaterial3D
	var g := Color.from_string("#808080", Color.WHITE).r
	_check("лессировка умножает цвет модели и оставляет текстуру",
		tint.albedo_texture != null and tint.albedo_color.is_equal_approx(Color(0.2 * g, 0.4 * g, 0.6 * g, 1.0)))

	VariantApplier.apply([mi], {})
	_check("пустое исполнение снимает покраску", mi.get_surface_override_material(0) == null and mi.get_surface_override_material(1) == null)

	# чужой override сохраняется и возвращается
	var foreign := _std(Color.YELLOW, false)
	mi.set_surface_override_material(0, foreign)
	VariantApplier.apply([mi], _paint({"all": ["#ff0000", "keep", true]}))
	var over := mi.get_surface_override_material(0)
	_check("чужой override стал основой покраски и запомнен", over != foreign and over.has_meta(VariantApplier.META_PREV)
		and over.get_meta(VariantApplier.META_PREV) == foreign)
	VariantApplier.apply([mi], {})
	_check("после сброса чужой override на месте", mi.get_surface_override_material(0) == foreign)

	# не BaseMaterial3D и пустая поверхность пропускаются
	var shader_mi := _mesh_node("Sh", [ShaderMaterial.new(), null])
	VariantApplier.apply([shader_mi], _paint({"all": ["#ff0000", "keep", true]}))
	_check("ShaderMaterial и поверхность без материала пропускаются", shader_mi.get_surface_override_material(0) == null and shader_mi.get_surface_override_material(1) == null)
	var junk := Node.new()
	VariantApplier.apply([null, junk], _paint({"all": ["#ff0000", "keep", true]}))
	_check("мусор в списке мешей не роняет", true)
	junk.free()
	shader_mi.free()
	mi.free()


# --- сущность ---

func _test_entity() -> void:
	var setting: EntitySetting = null
	for s in EntityCatalogProvider.load_all():
		if s.get_key() == KEY:
			setting = s
	_check("объект %s есть в каталоге" % KEY, setting != null)
	if setting == null:
		return
	var factory := EntityFactory.new()
	add_child(factory)
	var variant := ModelVariant.new()
	variant.id = "t1"
	variant.base = String(KEY)
	PaintData.set_zone(variant.paint, "all", Color.from_string("#c0392b", Color.WHITE), "matte")
	var e := factory.create_from_setting(setting, &"", variant.to_dict())
	add_child(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var vis := e.get_comp(C_Visual) as C_Visual
	_check("у сущности исполнение и есть визуал с мешами", e.variant.has("paint") and vis != null and not vis.mesh_nodes.is_empty())
	if vis != null:
		var painted := 0
		for m in vis.mesh_nodes:
			for i in m.mesh.get_surface_count():
				var o := m.get_surface_override_material(i)
				if o != null and o.has_meta(VariantApplier.META):
					painted += 1
		_check("меши кузова перекрашены (поверхностей: %d)" % painted, painted > 0)
		_count_painted_outside(vis.instance, vis.mesh_nodes, stray_counter)
		_check("тележки и колёса не покрашены", stray_counter[0] == 0)
	var saved := e.save_entity()
	_check("сейв сущности содержит исполнение", saved.has("variant") and (saved["variant"] as Dictionary).has("paint"))
	var plain := factory.create_from_setting(setting)
	add_child(plain)
	await get_tree().process_frame
	_check("у обычной сущности ключа variant в сейве нет", not plain.save_entity().has("variant"))
	e.kill_me()
	plain.kill_me()
	factory.queue_free()


var stray_counter: Array[int] = [0]


func _count_painted_outside(node: Node, body: Array[MeshInstance3D], counter: Array[int]) -> void:
	if node is MeshInstance3D and not body.has(node):
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var o := mi.get_surface_override_material(i)
				if o != null and o.has_meta(VariantApplier.META):
					counter[0] += 1
	for c in node.get_children():
		_count_painted_outside(c, body, counter)


# --- служебное ---

func _check(title: String, cond: bool) -> void:
	_all += 1
	if cond:
		_ok += 1
		print("PASS  ", title)
	else:
		print("FAIL  ", title)
