class_name RoomRoot extends Node3D

########################
## Корень сцены комнаты (data/rooms/<id>/<id>.tscn). Контракт: что RoomBuilder ждёт от сцены.
########################
## Сцену можно крутить в редакторе: двигать блоки, лампы, добавлять новые. Мир в см, центр комнаты (0, 0),
## столешница подмакетника на y = 0, пол на RoomConfig.floor_y (паспорт <id>.tres рядом со сценой).
##
## Дети корня по именам (всё необязательное, кроме нужного вам):
##   Floor     пол (visual layer комнаты)
##   Shell     стены, скос, рама окна, шторы: всё в нём получает слой оболочки (SkyFill его не видит) и отбрасывает тень в Observe
##   Ceiling   потолок: ребёнок CeilingSlab (MeshInstance3D). Кнопка «Потолок» и тень потолка идут через него
##   Decor     мебель и декор T1
##   DecorT2   мелочи, видны при QualityPreset.room_detail_lod >= 1
##   DecorT3   мелочи, видны при room_detail_lod >= 2
##   FakeAO    ложные AO-квады
##   Lights    SpotLight3D / OmniLight3D комнаты: RoomBuilder выносит их из комнаты, кнопка «Комната» свет не гасит
## Всё остальное считается декором. Меш с слоем по умолчанию (1) вне Shell получает visual layer комнаты, поэтому слой у новых блоков
## выставлять не нужно. Коллизия: StaticBody3D со слоем room (бит 8). Меш с именем SkyCard* попадает в группу gfx_sky (небо в окне).
## Меш с именем Bulb* светится, пока включена лампа (StandardMaterial3D, emission).
## Лампы на сцене работают так же, как раньше RoomConfig.lamps: энергия и тень настраиваются на самой ноде.
## Добавлять в паспорт <id>.tres lamps не нужно (массив пустой).

const SHELL := "Shell"
const CEILING := "Ceiling"
const LIGHTS := "Lights"
const WALL_GROUP := &"room_wall"   # доп. способ пометить меш как стену (тень в Observe), если он не в Shell

var _shell_layer := 0
var _vis_layer := 0


## Слои и группы. Вызывает RoomBuilder сразу после instantiate (до добавления в дерево)
func setup(vis_layer: int, shell_layer: int) -> void:
	_vis_layer = vis_layer
	_shell_layer = shell_layer
	for n in _all_nodes(self):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if _in_shell(mi):
				mi.layers = shell_layer
			elif mi.layers & 1:
				mi.layers = vis_layer
		if String(n.name).begins_with("SkyCard") and not n.is_in_group(&"gfx_sky"):
			n.add_to_group(&"gfx_sky")


## Лампы комнаты отдельной нодой (RoomBuilder ставит её рядом с комнатой). null, если ламп нет
func take_lights() -> Node3D:
	var l := get_node_or_null(LIGHTS) as Node3D
	if l:
		remove_child(l)
	return l


## Меши, отбрасывающие тень только в Observe: всё в Shell (кроме потолка) и меши группы room_wall
func get_wall_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in _all_nodes(self):
		if n is MeshInstance3D and (_in_shell(n) or n.is_in_group(WALL_GROUP)) and not _in_ceiling(n):
			out.append(n)
	return out


func get_ceiling() -> Node3D:
	return get_node_or_null(CEILING) as Node3D


func get_ceiling_mesh() -> MeshInstance3D:
	var c := get_ceiling()
	if c == null:
		return null
	return c.get_node_or_null("CeilingSlab") as MeshInstance3D


## Мелочи по QualityPreset.room_detail_lod (0: только T1, 1: T1 + T2, 2: все)
func set_detail(lod: int) -> void:
	var t2 := get_node_or_null("DecorT2") as Node3D
	if t2:
		t2.visible = lod >= 1
	var t3 := get_node_or_null("DecorT3") as Node3D
	if t3:
		t3.visible = lod >= 2


## Лампочки (меши Bulb*) светятся, когда лампа включена (GFX.lamp_changed)
func set_lamp_glow(on: bool) -> void:
	for n in _all_nodes(self):
		if n is MeshInstance3D and String(n.name).begins_with("Bulb"):
			var m := (n as MeshInstance3D).material_override as StandardMaterial3D
			if m:
				m.emission_enabled = on


func _in_shell(n: Node) -> bool:
	return _under(n, SHELL) or _in_ceiling(n)


func _in_ceiling(n: Node) -> bool:
	return _under(n, CEILING)


## n лежит внутри прямого ребёнка корня с этим именем
func _under(n: Node, top: String) -> bool:
	var p := n
	while p != null and p != self:
		if p.get_parent() == self:
			return String(p.name) == top
		p = p.get_parent()
	return false


func _all_nodes(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in from.get_children():
		out.append(c)
		out.append_array(_all_nodes(c))
	return out
