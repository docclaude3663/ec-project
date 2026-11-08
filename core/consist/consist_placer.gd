class_name ConsistPlacer extends RefCounted

###########################
## ConsistPlacer. Постановка состава из шаблона на рельсы
###########################
## Головная часть ставится BuildTool как обычный объект (призрак, клик). Здесь считаются места остальных частей
## вдоль пути (RailWalker), создаются сами части, садятся на рельсы (C_Chassis.on_train_snapped с тележками
## на своих траках) и сцепляются (C_Coupler.couple_with).
##
## Направление: шаблон записан от головной части. reversed=false - часть передним торцом (FRONT) к головной,
## то есть смотрит «к голове»; reversed=true - наоборот. Хвост лежит позади головной части, если она
## не reversed, и впереди неё, если reversed. Расстояние между центрами берётся из шаблона по прямой (spacing).


## Состояния центров всех частей на рельсах, головная первой. Пусто: состав не помещается
## (головная не на рельсах или путь кончился раньше хвоста).
## snap: {"track": Entity, "offset": float, "route": int} - посадка головной
static func plan(cs: ConsistSetting, head: Entity, snap: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cs == null or head == null or snap.is_empty():
		return out
	var parts := cs.template.parts
	var head_fwd := -head.global_basis.z
	var tail_dir := head_fwd if parts[0].get("reversed", false) else -head_fwd
	var st := RailWalker.from_snap(snap.track, snap.route, snap.offset, tail_dir)
	if st.is_empty():
		return out
	out.append(st)
	for i in range(1, parts.size()):
		st = RailWalker.advance(st, float(parts[i].get("spacing", 0.0)))
		if st.is_empty():
			out.clear()
			return out
		out.append(st)
	return out


## Ставит остальные части и сцепляет состав. head - уже поставленная головная часть.
## Возвращает все части по порядку (головная первой); при неудаче только головную
static func spawn(cs: ConsistSetting, head: Entity, snap: Dictionary, factory: EntityFactory, root: Node) -> Array[Entity]:
	var result: Array[Entity] = [head]
	var states := plan(cs, head, snap)
	if states.is_empty():
		push_warning("Consist: состав '%s' не поместился на путь, поставлена только головная часть" % cs.name)
		return result
	var parts := cs.template.parts

	# Головная: на рельсы, если её туда ещё не посадили
	_seat(head, parts[0], states[0], false)

	for i in range(1, parts.size()):
		var e := factory.create_from_setting(cs.part_settings[i], &"", {})
		root.add_child(e)
		_seat(e, parts[i], states[i], true)
		result.append(e)

	# Сцепки: выходной торец предыдущей части со входным торцом следующей
	for i in range(1, result.size()):
		var a := result[i - 1].get_comp(C_Coupler) as C_Coupler
		var b := result[i].get_comp(C_Coupler) as C_Coupler
		if a == null or b == null:
			continue
		var a_end := C_Coupler.FRONT if parts[i - 1].get("reversed", false) else C_Coupler.REAR
		var b_end := C_Coupler.REAR if parts[i].get("reversed", false) else C_Coupler.FRONT
		if not a.couple_with(a_end, b, b_end):
			push_warning("Consist: не сцеплены части %d и %d шаблона '%s' (типы сцепок или торцы)" % [i, i + 1, cs.name])
	return result


## Садит часть на рельсы по состоянию центра. place: сначала поставить в точку (у головной она уже стоит)
static func _seat(e: Entity, part: Dictionary, state: Dictionary, place: bool) -> void:
	var ch := e.get_comp(C_Chassis) as C_Chassis
	var bg := e.get_comp(C_Bogie) as C_Bogie
	if ch == null or bg == null:
		return
	var heading := RailWalker.heading(state)
	var fwd := heading if part.get("reversed", false) else -heading
	if place:
		var basis := e.global_basis
		if absf(fwd.y) < 0.99:
			basis = Basis.looking_at(fwd, Vector3.UP)
		e.global_transform = Transform3D(basis, RailWalker.body_point(state))
	elif ch.is_on_rails:
		return

	# Каждая тележка на своём траке: часть может стоять на стыке
	var hits: Array[Dictionary] = []
	var same := fwd.dot(heading) >= 0.0
	for b in bg.bogies_data:
		var z: float = b.pivot.position.z
		var along := -z if same else z   # >= 0: по ходьбе вперёд
		var s2 := RailWalker.advance(state, along) if along >= 0.0 else RailWalker.advance(RailWalker.reversed(state), -along)
		if s2.is_empty():
			continue
		hits.append({"bogie_id": b.id, "track": s2.track, "route": s2.route, "distance": s2.dist})
	ch.on_train_snapped({"track": state.track, "offset": state.dist, "route": state.route, "bogie_hits": hits})
