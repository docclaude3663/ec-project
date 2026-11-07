class_name RailNetBuilder extends RefCounted

#####################
## Сборка графа цепей из сущностей (ATTN_10 §10.5.4, D1)
#####################
## Заменяет обход в ширину из `PowerGridManager`. Узел графа это пара «сущность, луч питания»
## (`C_PowerTrack.legs`), ребро это стык двух траков по сокетам (`C_Socket.get_electric_neighbors`,
## `is_socket_live`, `is_gap`). Цепь это компонент связности. Питание в цепь подают клипы (`C_PowerClip`):
##  - лидер цепи: клип с наименьшим номером контура (при равных по `get_instance_id`), он задаёт номер цепи;
##  - клип с тем же номером: параллельная подача, не конфликт;
##  - клип с другим номером (политика MERGE): цепь питает лидер, клип остаётся, помечается `conflict = "label"`;
##  - полярность клипа: цепь согласована, если `flip(трак) == clip.feed_reversed()`. Иначе у клипа `conflict = "polarity"`
##    и цепь в КЗ (провода между точками подачи перепутаны);
##  - ребро, не сошедшееся по чётности (реверсивная петля без изостыков), тоже КЗ цепи.
## Цепь без клипа получает номер 0 (как раньше).
##
## Объект хранит только список сущностей, виденных в прошлый раз: новые траки считаются изменившимися,
## чтобы слой питания обновил их вид (раньше это делала рассылка всем тракам при каждом пересчете).

## Сущности, учтённые прошлым расчётом (для определения «новых»)
var _known: Dictionary = {}
## false (D7, правило gaps_enabled): изостыки не разрывают цепь
var gaps_enabled := true


## Расчёт сети. Результат:
##  "changed": Array[Entity] - траки, у которых изменились цепь, полярность или авария (обновить вид);
##  "nets": Dictionary номер цепи -> {"feeders": int, "tracks": int, "conflicts": int, "short": bool};
##  "shorts": Array[int] - номера цепей в КЗ;
##  "graph": RailNetGraph (для тестов и отладки).
func solve(tree: SceneTree, clips: Array) -> Dictionary:
	var ents: Array[Entity] = []
	var powers: Array[C_PowerTrack] = []
	var socks: Array = []
	var first_node: Array[int] = []
	var index_of: Dictionary = {}
	var graph := RailNetGraph.new()
	var node_count := 0

	# 1. Узлы: траки, у которых есть C_PowerTrack. Призраки и удаляемые не участвуют
	for n in tree.get_nodes_in_group("power_track"):
		var e := n as Entity
		if e == null or not is_instance_valid(e) or e.is_queued_for_deletion() or e.has_comp(C_Ghost):
			continue
		var pt := e.get_comp(C_PowerTrack) as C_PowerTrack
		if pt == null:
			continue
		index_of[e] = ents.size()
		ents.append(e)
		powers.append(pt)
		socks.append(e.get_comp(C_Socket))
		first_node.append(node_count)
		for leg in pt.legs:
			graph.add_node(node_count + leg)
		node_count += pt.legs

	# 2. Рёбра: стыки. Пара сущностей обрабатывается один раз
	var seen: Dictionary = {}
	for i in ents.size():
		var sock_i := socks[i] as C_Socket
		if sock_i == null:
			continue
		for nb in sock_i.get_electric_neighbors():
			if not index_of.has(nb):
				continue
			var j: int = index_of[nb]
			if j == i:
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			if seen.has(key):
				continue
			seen[key] = true
			_add_joint(graph, ents, powers, socks, first_node, i, j)

	# 3. Клипы по компонентам
	for c in clips:
		if not is_instance_valid(c):   # клип мог быть освобожден без on_removed (free сущности): приведение типа упало бы
			continue
		var clip := c as C_PowerClip
		if clip != null:
			clip.conflict = ""
			clip.conflict_with = 0
	var feeders: Dictionary = {}   # корень -> Array[C_PowerClip]
	for c in clips:
		if not is_instance_valid(c):
			continue
		var clip := c as C_PowerClip
		if clip == null:
			continue
		if clip.feed_net() == 0 or clip.entity == null or not is_instance_valid(clip.entity):
			continue
		if not index_of.has(clip.entity):
			continue
		var root: Variant = graph.root_of(first_node[index_of[clip.entity]])
		if not feeders.has(root):
			feeders[root] = []
		feeders[root].append(clip)

	# 4. Лидеры, конфликты клипов и КЗ по компонентам
	var leaders: Dictionary = {}     # корень -> C_PowerClip
	var leader_nodes: Dictionary = {}   # корень -> узел лидера (луч 0 его трака)
	var short_roots: Dictionary = {}  # корень -> true
	var fault_nodes: Dictionary = {}  # узел -> true (где замыкание)
	var net_conflicts: Dictionary = {}   # корень -> число конфликтных клипов
	for root in feeders:
		var arr: Array = feeders[root]
		arr.sort_custom(_clip_less)
		leaders[root] = arr[0]
		leader_nodes[root] = first_node[index_of[(arr[0] as C_PowerClip).entity]]
	for cf in graph.conflicts:
		var r: Variant = graph.root_of(cf.a)
		short_roots[r] = true
		fault_nodes[cf.a] = true
		fault_nodes[cf.b] = true
	for root in feeders:
		var arr: Array = feeders[root]
		var leader: C_PowerClip = leaders[root]
		for k in range(1, arr.size()):
			var clip: C_PowerClip = arr[k]
			if clip.feed_net() != leader.feed_net():
				clip.conflict = "label"
				clip.conflict_with = leader.feed_net()
				net_conflicts[root] = int(net_conflicts.get(root, 0)) + 1
				continue
			var node: int = first_node[index_of[clip.entity]]
			if _flip_at(graph, leaders[root], leader_nodes[root], node) != clip.feed_reversed():
				clip.conflict = "polarity"
				short_roots[root] = true
				fault_nodes[node] = true
				net_conflicts[root] = int(net_conflicts.get(root, 0)) + 1

	# 5. Запись в траки, только то, что изменилось
	var changed: Array[Entity] = []
	var nets: Dictionary = {}
	var shorts: Array[int] = []
	var known_now: Dictionary = {}
	var tracks_of_root: Dictionary = {}
	var dead_ref: Dictionary = {}   # корень цепи без питания -> узел-эталон направления (см. ниже)
	var roots_of: Dictionary = {}   # сущность -> корень связного участка (луч 0), для датчиков занятости (D6)
	for i in ents.size():
		var pt := powers[i]
		roots_of[ents[i]] = graph.root_of(first_node[i])
		var touched := not _known.has(ents[i])
		known_now[ents[i]] = true
		var fault := false
		for leg in pt.legs:
			var node := first_node[i] + leg
			var root: Variant = graph.root_of(node)
			var net := 0
			var flip := false
			if leaders.has(root):
				net = (leaders[root] as C_PowerClip).feed_net()
				flip = _flip_at(graph, leaders[root], leader_nodes[root], node)
				tracks_of_root[root] = int(tracks_of_root.get(root, 0)) + 1
			else:
				# Без питания. Номер цепи 0, но flip нужен физике: тележка по нему выбирает направление хода по сплайну
				# (C_Bogie dir_sign). Если оставить false у всех, то на стыке траков, чьи сплайны смотрят навстречу,
				# катящийся вагон разворачивается на 180. Эталон направления - первый узел компоненты
				if not dead_ref.has(root):
					dead_ref[root] = node
				flip = graph.flip_between(node, dead_ref[root])
			if pt.contour_of(leg) != net or pt.flip_of(leg) != flip:
				pt.set_leg(leg, net, flip)
				touched = true
			if fault_nodes.has(node):
				fault = true
		if pt.fault != fault:
			pt.fault = fault
			touched = true
		if touched:
			changed.append(ents[i])
	_known = known_now

	# 6. Сводка по цепям
	for root in leaders:
		var net_id: int = (leaders[root] as C_PowerClip).feed_net()
		var info: Dictionary = nets.get(net_id, {"feeders": 0, "tracks": 0, "conflicts": 0, "short": false})
		info["feeders"] += (feeders[root] as Array).size()
		info["tracks"] += int(tracks_of_root.get(root, 0))
		info["conflicts"] += int(net_conflicts.get(root, 0))
		if short_roots.has(root):
			info["short"] = true
			if not shorts.has(net_id):
				shorts.append(net_id)
		nets[net_id] = info

	return {"changed": changed, "nets": nets, "shorts": shorts, "graph": graph, "roots": roots_of}


# ------------------------------------------------------------------

## Порядок клипов в цепи: меньший номер контура первый, при равных меньший instance id
static func _clip_less(a: C_PowerClip, b: C_PowerClip) -> bool:
	if a.feed_net() != b.feed_net():
		return a.feed_net() < b.feed_net()
	return a.get_instance_id() < b.get_instance_id()


## Развёрнутость узла относительно эталона цепи: parity(узла) xor parity(узла лидера) xor лидер.reversed.
## У самого лидера это его `reversed`: «поменять полярность» на лидере разворачивает всю цепь
static func _flip_at(graph: RailNetGraph, leader: C_PowerClip, leader_node: int, node: int) -> bool:
	return (graph.parity_of(node) != graph.parity_of(leader_node)) != leader.feed_reversed()


## Ребро между двумя траками по их стыку. Стык не проводит, если сокет мёртв (E1) или есть изостык
func _add_joint(graph: RailNetGraph, ents: Array[Entity], powers: Array[C_PowerTrack],
		socks: Array, first_node: Array[int], i: int, j: int) -> void:
	var sa := socks[i] as C_Socket
	var sb := socks[j] as C_Socket
	var joint := find_joint(ents[i], ents[j])
	var leg_a := 0
	var leg_b := 0
	var flip := false
	if not joint.is_empty() and sa != null and sb != null:
		var ia: int = joint.id1
		var ib: int = joint.id2
		if not sa.is_socket_live(ia) or not sb.is_socket_live(ib):
			return
		if gaps_enabled and (sa.is_gap(ia) or sb.is_gap(ib)):
			return
		leg_a = sa.leg_of_socket(ia)
		leg_b = sb.leg_of_socket(ib)
		flip = joint_flip(sa, sb, ia, ib)
	graph.add_edge(first_node[i] + clampi(leg_a, 0, powers[i].legs - 1),
			first_node[j] + clampi(leg_b, 0, powers[j].legs - 1), flip)


## Стык двух сущностей: индексы ближайших друг к другу сокетов {id1, id2}. Пусто, если у кого-то нет сокетов или пути
static func find_joint(a: Entity, b: Entity) -> Dictionary:
	var sock_a := a.get_comp(C_Socket) as C_Socket
	var sock_b := b.get_comp(C_Socket) as C_Socket
	var path_a := a.get_comp(C_Path) as C_Path
	var path_b := b.get_comp(C_Path) as C_Path
	if not sock_a or not sock_b or not path_a or not path_b:
		return {}
	var min_dist := INF
	var id1 := 0
	var id2 := 0
	# точные глобальные координаты через Path3D (не через Entity)
	for i in range(sock_a.sockets.size()):
		var p1: Vector3 = path_a.path_node.to_global(sock_a.sockets[i].pos)
		for j in range(sock_b.sockets.size()):
			var p2: Vector3 = path_b.path_node.to_global(sock_b.sockets[j].pos)
			var dist := p1.distance_squared_to(p2)
			if dist < min_dist:
				min_dist = dist
				id1 = i
				id2 = j
	return {"id1": id1, "id2": id2}


## Полярность на стыке: начало к началу или конец к концу разворачивает, начало к концу нет.
## Начало маршрута берется из флага сокета `start` (у кросса два начала), без флага это сокет 0
static func joint_flip(sa: C_Socket, sb: C_Socket, ia: int, ib: int) -> bool:
	var start_a := ia == 0
	var start_b := ib == 0
	if ia < sa.sockets.size():
		start_a = bool(sa.sockets[ia].get("start", ia == 0))
	if ib < sb.sockets.size():
		start_b = bool(sb.sockets[ib].get("start", ib == 0))
	return start_a == start_b
