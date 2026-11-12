extends Node

# XX claude-library (новый файл)
## Проверка шага C2.1b (ATTN_22): слои кисти в исполнении без рендера: PaintData (слои с текстурой), файлы слоёв и
## встраивание PNG (VariantIO), PNG в накладку с общим кэшем (PaintLayers), накладка слоя в цепочке материалов.
## Запуск: открыть tests/library_paint_layers_test.tscn и нажать F6.
## Итог в Output: строки PASS/FAIL и «Library paint layers: n/m». Временные файлы в user://library_layers_test.

const TMP := "user://library_layers_test"

var _ok := 0
var _all := 0


func _ready() -> void:
	_rm_tree(TMP)
	_test_data()
	_test_files()
	_test_png_and_overlays()
	_test_applier()
	_rm_tree(TMP)
	print("Library paint layers: %d/%d" % [_ok, _all])
	get_tree().quit(0 if _ok == _all else 1)


func _png(color: Color, size := 4) -> PackedByteArray:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


# --- данные слоя ---

func _test_data() -> void:
	var p := PaintData.new_paint()
	_check("новая покраска: слоёв с текстурой нет, is_blank", not PaintData.has_texture_layers(p) and PaintData.is_blank(p))
	PaintData.set_texture_layer(p, "p1", "Body", 1024, "p1.png")
	var layers := PaintData.texture_layers(p)
	_check("слой кисти создан: меш, файл, премультипликация", layers.size() == 1 and layers[0]["mesh"] == "Body" and layers[0]["file"] == "p1.png"
		and layers[0]["premultiplied"] == true and not layers[0].has("data"))
	_check("со слоем кисти покраска не пуста", not PaintData.is_blank(p) and PaintData.is_empty(p))
	PaintData.set_texture_layer(p, "p1", "Body", 1024, "", PackedByteArray([1, 2, 3]))
	_check("set_texture_layer заменяет слой, а не дублирует; data внутри", PaintData.texture_layers(p).size() == 1
		and PaintData.texture_layers(p)[0]["data"] == PackedByteArray([1, 2, 3]) and not PaintData.texture_layers(p)[0].has("file"))
	PaintData.set_zone(p, "all", Color.RED)
	_check("слой кисти и заливка зон живут вместе", PaintData.zone_spec(p, "all")["color"] == "#ff0000" and PaintData.has_texture_layers(p))
	PaintData.remove_texture_layer(p, "p1")
	_check("remove_texture_layer убирает слой, заливка остаётся", not PaintData.has_texture_layers(p) and not PaintData.is_empty(p))
	PaintData.remove_texture_layer(p, "нет_такого")
	_check("удаление несуществующего слоя не роняет", true)


# --- файлы слоёв ---

func _test_files() -> void:
	var png := _png(Color.RED)
	var v := ModelVariant.new()
	v.id = "lay1"
	v.base = "train.test.one"
	PaintData.set_texture_layer(v.paint, "p1", "Body", 4, "p1.png", png)
	_check("save_layers записывает PNG", VariantIO.save_layers(v.id, {"p1.png": png}, TMP) == OK)
	_check("load_layer_png читает те же байты", VariantIO.load_layer_png(v.id, "p1.png", TMP) == png)
	_check("save_variant пишет JSON без байт PNG", VariantIO.save_variant(v, TMP) == OK)
	var text := FileAccess.get_file_as_string(VariantIO.variant_path(v.id, TMP))
	_check("в JSON слой кисти есть, поля data нет", text.contains("\"coverage\": \"texture\"") and text.contains("p1.png") and not text.contains("\"data\""))
	var back := VariantIO.load_variant(v.id, TMP)
	_check("исполнение со слоем кисти читается из JSON", back != null and PaintData.texture_layers(back.paint).size() == 1
		and PaintData.texture_layers(back.paint)[0]["file"] == "p1.png")
	var embedded := VariantIO.embed_layers(back.to_dict(), v.id, TMP)
	var el := PaintData.texture_layers(embedded["paint"])
	_check("embed_layers кладёт PNG внутрь словаря (копия, оригинал цел)", el.size() == 1 and el[0]["data"] == png
		and not PaintData.texture_layers(back.paint)[0].has("data"))
	_check("недопустимые имена файлов слоя", not VariantIO.is_valid_layer_file("../x.png") and not VariantIO.is_valid_layer_file("a.jpg")
		and not VariantIO.is_valid_layer_file("a b.png") and VariantIO.is_valid_layer_file("p1.png"))
	_check("save_layers с недопустимым именем отклоняется", VariantIO.save_layers(v.id, {"../x.png": png}, TMP) == ERR_INVALID_PARAMETER)
	_check("load_layer_png с недопустимыми именами пуст", VariantIO.load_layer_png("../x", "p1.png", TMP).is_empty() and VariantIO.load_layer_png(v.id, "../p1.png", TMP).is_empty())
	_check("файл слоя после неудачной записи цел", VariantIO.load_layer_png(v.id, "p1.png", TMP) == png)
	VariantIO.save_layers(v.id, {}, TMP)
	_check("save_layers с пустым словарём чистит файлы слоёв", VariantIO.load_layer_png(v.id, "p1.png", TMP).is_empty()
		and not DirAccess.dir_exists_absolute(VariantIO.layer_dir(v.id, TMP)))
	VariantIO.save_layers(v.id, {"p1.png": png}, TMP)
	_check("delete_variant удаляет и JSON, и папку слоёв", VariantIO.delete_variant(v.id, TMP) == OK
		and not DirAccess.dir_exists_absolute(VariantIO.layer_dir(v.id, TMP)) and VariantIO.load_variant(v.id, TMP) == null)


# --- PNG в накладку ---

func _test_png_and_overlays() -> void:
	PaintLayers.clear_cache()
	var png := _png(Color(1, 0, 0, 1))
	var t1 := PaintLayers.texture_from_png(png)
	var t2 := PaintLayers.texture_from_png(png)
	_check("PNG читается в текстуру, одинаковые байты дают одну текстуру (кэш)", t1 != null and t1 == t2)
	_check("другие байты дают другую текстуру", PaintLayers.texture_from_png(_png(Color(0, 0, 1, 1))) != t1)
	_check("мусор вместо PNG даёт null, пустой массив тоже", PaintLayers.texture_from_png(PackedByteArray([1, 2, 3, 4])) == null and PaintLayers.texture_from_png(PackedByteArray()) == null)
	var mat := PaintLayers.make_overlay(t1)
	_check("накладка: шейдер и текстура слоя", mat.shader != null and mat.get_shader_parameter("layer") == t1)

	var p := PaintData.new_paint()
	PaintData.set_texture_layer(p, "p1", "Body", 4, "", png)
	var ov := PaintLayers.overlays_from({"paint": p})
	_check("overlays_from: накладка по имени меша", ov.has("Body") and ov["Body"] is ShaderMaterial and ov["Body"].get_shader_parameter("layer") == t1)
	PaintData.texture_layers(p)[0]["visible"] = false
	_check("скрытый слой пропускается", PaintLayers.overlays_from({"paint": p}).is_empty())
	var p2 := PaintData.new_paint()
	PaintData.set_texture_layer(p2, "p1", "Body", 4, "p1.png")
	_check("слой без data (только файл) в игровую накладку не попадает", PaintLayers.overlays_from({"paint": p2}).is_empty())
	_check("исполнение без покраски и мусор не роняют", PaintLayers.overlays_from({}).is_empty() and PaintLayers.overlays_from({"paint": 5}).is_empty())


# --- применение к мешам ---

func _test_applier() -> void:
	var tail := StandardMaterial3D.new()
	var base := StandardMaterial3D.new()
	base.next_pass = tail
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	mesh.surface_set_material(0, base)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	var p := PaintData.new_paint()
	PaintData.set_texture_layer(p, "p1", "Body", 4, "", _png(Color(1, 0, 0, 1)))
	VariantApplier.apply([mi], {"paint": p})
	var o := mi.get_surface_override_material(0)
	_check("слой кисти из данных исполнения встал накладкой, прежняя цепочка за ней",
		o != null and o.has_meta(VariantApplier.META) and o.next_pass is ShaderMaterial and (o.next_pass as Material).next_pass == tail and base.next_pass == tail)
	var live := ShaderMaterial.new()
	VariantApplier.apply([mi], {"paint": p}, {"Body": live})
	var o2 := mi.get_surface_override_material(0)
	_check("живая накладка Library главнее слоя из данных", o2.next_pass is ShaderMaterial and (o2.next_pass as ShaderMaterial).shader == live.shader)
	VariantApplier.apply([mi], {})
	_check("пустое исполнение снимает накладку слоя", mi.get_surface_override_material(0) == null)
	mi.free()


func _rm_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func _check(title: String, cond: bool) -> void:
	_all += 1
	if cond:
		_ok += 1
		print("PASS  ", title)
	else:
		print("FAIL  ", title)
