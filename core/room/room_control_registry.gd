class_name RoomControlRegistry extends RefCounted

########################
## Реестр управляемых объектов комнаты (ATTN_25 §25.6, RM5)
########################
## Собирает описания RoomControlDef из сцены комнаты: метки RoomControl (источник «сцена Godot»). Источник .glb добавит RM8.
## Читают реестр вкладка «Объекты» Room Studio и (RM6) карточки Observe → Light. Нарушения правил не бросают: собираются
## в warnings (повтор id, объект не того типа, механизм без анимации), остальное продолжает работать.
## Собирать надо до RoomRoot.take_lights(): метки лежат в ветке ламп.

var defs: Array[RoomControlDef] = []
var warnings := PackedStringArray()

var _by_key := {}   # StringName -> RoomControlDef (ключ: group, иначе id)


## Все метки RoomControl под root (включая сам root) -> реестр. Значения приводятся к default_value
static func collect(root: Node, owner_name := "") -> RoomControlRegistry:
	var reg := RoomControlRegistry.new()
	if root == null:
		return reg
	var on := owner_name if owner_name != "" else String(root.name)
	reg._walk(root, on)
	for d in reg.defs:
		d.reset()
	return reg


func by_id(id: StringName) -> RoomControlDef:
	return _by_key.get(id) as RoomControlDef


## Управления с этим scope (OBSERVE: для Observe → Light; STUDIO: только студия)
func for_scope(scope: RoomControl.Scope) -> Array[RoomControlDef]:
	var out: Array[RoomControlDef] = []
	for d in defs:
		if d.scope == scope:
			out.append(d)
	return out


## Шаг механизмов (владелец зовёт каждый кадр, пока что-то движется)
func tick(dt: float) -> void:
	for d in defs:
		d.tick(dt)


func is_moving() -> bool:
	for d in defs:
		if d.is_moving():
			return true
	return false


## Всё в начальные значения
func reset() -> void:
	for d in defs:
		d.reset()


func _walk(n: Node, owner_name: String) -> void:
	if n is RoomControl:
		_add(n as RoomControl, owner_name)
	for c in n.get_children():
		_walk(c, owner_name)


func _add(c: RoomControl, owner_name: String) -> void:
	var target := c.get_parent()
	var key: StringName = c.group if c.group != &"" else c.id
	if key == &"":
		warnings.append("метка RoomControl у '%s' без id" % target.name)
		return
	var d := _by_key.get(key) as RoomControlDef
	if d == null:
		d = RoomControlDef.new()
		d.id = key
		d.kind = c.kind
		d.scope = c.scope
		d.title = c.title
		d.default_value = c.default_value
		d.group = c.group
		if d.add_node(target, c.mechanism, owner_name):
			defs.append(d)
			_by_key[key] = d
		else:
			warnings.append("управление '%s' на узле '%s' не создано (см. Output)" % [key, target.name])
		return
	# Тот же ключ: общее управление группы или повтор id
	if c.group == &"" or d.group == &"":
		warnings.append("повтор id '%s' (узел '%s'): id должен быть уникален в комнате" % [key, target.name])
		return
	if c.kind != d.kind or c.scope != d.scope:
		warnings.append("группа '%s': у узла '%s' другие kind или scope, метка пропущена" % [key, target.name])
		return
	if not d.add_node(target, c.mechanism, owner_name):
		warnings.append("группа '%s': узел '%s' не добавлен (см. Output)" % [key, target.name])
