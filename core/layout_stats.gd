class_name LayoutStats extends Node

# U9 (ATTN_17 §17.4): новый файл
## Статистика макета для TopBar: траки, длина, вагоны, составы, занятые контуры, прочие объекты.
## Сущности лежат в EntitiesRoot. Добавление и удаление ловим по сигналам детей, сцепки и контуры
## меняются без этого, поэтому раз в REFRESH секунд пересчитываем и без сигнала.
## Пересчёт не чаще MAX_HZ раз в секунду; `changed` только если число поменялось.
## Призраки (C_Ghost) и сущности на удалении не считаются.

## ⚡ Хотя бы одно значение статистики изменилось
signal changed

const MAX_HZ := 4.0
## Проверка без сигнала добавления или удаления (сцепка, назначение контура), с
const REFRESH := 1.0

## Поля читаются по имени из StatSpec.key
var tracks := 0
var track_length := 0.0
var wagons := 0
## Составы: группы из двух и более вагонов, соединённых сцепкой. Одиночный вагон составом не считается
var consists := 0
var contours := 0
var others := 0

var _root: Node
var _dirty := true
var _since_calc := 0.0
var _since_refresh := 0.0


func _ready() -> void:
	_root = get_node_or_null("/root/GameRoot/EntitiesRoot")
	if _root:
		_root.child_entered_tree.connect(_mark_dirty.unbind(1))
		_root.child_exiting_tree.connect(_mark_dirty.unbind(1))
	_recalc()


func _process(delta: float) -> void:
	_since_calc += delta
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_dirty = true
	if _dirty and _since_calc >= 1.0 / MAX_HZ:
		_recalc()


func _mark_dirty() -> void:
	_dirty = true


func _recalc() -> void:
	_dirty = false
	_since_calc = 0.0
	var n_tracks := 0
	var length := 0.0
	var wagon_list: Array[Entity] = []
	var n_others := 0
	if _root:
		for n in _root.get_children():
			var e := n as Entity
			if e == null or e.is_queued_for_deletion() or e.has_comp(C_Ghost) or e.has_comp(C_Destroying):
				continue
			if e.has_comp(C_Path) or e.has_comp(C_Switch):
				n_tracks += 1
				length += _path_length(e)
			elif e.has_comp(C_Bogie):
				wagon_list.append(e)
			elif not e.has_comp(C_TableSection):
				n_others += 1
	var n_consists := _count_consists(wagon_list)
	var n_contours := PGM.get_occupied_contours().size()

	var diff := n_tracks != tracks or not is_equal_approx(length, track_length) \
		or wagon_list.size() != wagons or n_consists != consists \
		or n_contours != contours or n_others != others
	tracks = n_tracks
	track_length = length
	wagons = wagon_list.size()
	consists = n_consists
	contours = n_contours
	others = n_others
	if diff:
		changed.emit()


## Длина трака: по кривой, если она есть (flex), иначе по паспорту (прямая, дуга)
func _path_length(e: Entity) -> float:
	var p := e.get_comp(C_Path) as C_Path
	if p == null:
		return 0.0
	if p.curve != null:
		var l := p.curve.get_baked_length()
		if l > 0.0:
			return l
	return p.get_length()


## Связные группы вагонов по сцепкам (два конца у каждого), считаем группы размером от двух
func _count_consists(wagon_list: Array[Entity]) -> int:
	var parent := {}   # instance_id вагона → instance_id корня группы
	for e in wagon_list:
		parent[e.get_instance_id()] = e.get_instance_id()
	for e in wagon_list:
		var cp := e.get_comp(C_Coupler) as C_Coupler
		if cp == null:
			continue
		for end in 2:
			var nb := cp.get_neighbor(end)
			if nb == null or nb.entity == null:
				continue
			var other_id := nb.entity.get_instance_id()
			if parent.has(other_id):
				_union(parent, e.get_instance_id(), other_id)
	var sizes := {}
	for id in parent:
		var r := _find(parent, id)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var n := 0
	for r in sizes:
		if sizes[r] >= 2:
			n += 1
	return n


func _find(parent: Dictionary, id: int) -> int:
	while parent[id] != id:
		parent[id] = parent[parent[id]]
		id = parent[id]
	return id


func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
