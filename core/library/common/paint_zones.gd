class_name PaintZones extends RefCounted

# XX claude-library (новый файл)
########################
## PaintZones. Зоны покраски модели: вся модель и каждая поверхность каждого меша (ATTN_22 §22.7.2.1, шаг L3)
########################
## id зоны: "all" или "<имя меша>#<номер поверхности>". Имя меша устойчивее порядка: после повторного экспорта
## из Blender номера поверхностей могут сместиться, а имя узла обычно остаётся.
## Название поверхности берётся из имени поверхности меша, иначе из имени материала; автор может задать своё
## в ModelInfo.zone_titles (id зоны -> название).

const ALL := PaintData.ALL


static func zone_id(mi: MeshInstance3D, surface: int) -> String:
	return "%s#%d" % [mi.name, surface]


## Прозрачный материал (стекло): зона «Весь корпус» его не трогает, чтобы окна оставались стеклом
static func is_transparent(mat: Material) -> bool:
	return mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## Список зон [{id, title, mesh, surface, transparent}]: первой «Весь корпус», дальше по поверхностям
static func list(meshes: Array, info: ModelInfo = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": ALL, "title": "Весь корпус", "mesh": "", "surface": -1, "transparent": false}]
	var many := meshes.size() > 1
	for mi in meshes:
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var node := mi as MeshInstance3D
		var mesh := node.mesh
		for i in mesh.get_surface_count():
			var id := zone_id(node, i)
			var mat := mesh.surface_get_material(i)
			var title := _auto_title(mesh, mat, i)
			if info != null and info.zone_titles.has(id):
				title = str(info.zone_titles[id])
			elif many:
				title = "%s: %s" % [node.name, title]
			out.append({"id": id, "title": title, "mesh": str(node.name), "surface": i, "transparent": is_transparent(mat)})
	return out


static func _auto_title(mesh: Mesh, mat: Material, surface: int) -> String:
	if mesh is ArrayMesh:
		var n := (mesh as ArrayMesh).surface_get_name(surface)
		if n != "":
			return n
	if mat != null and mat.resource_name != "":
		return mat.resource_name
	return "Поверхность %d" % (surface + 1)
