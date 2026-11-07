class_name LibraryCatalog extends VBoxContainer

# XX claude-library (новый файл)
########################
## LibraryCatalog. Каталог слева в экране Library: поиск, категория, фильтры, дерево (ATTN_22 §22.7.1, шаг L2)
########################
## Источник один: EntityCatalogProvider.load_all() по Global.object_dirs (как у каталога игры и lint).
## Фильтры берутся из CatalogMeta.filter_specs(категория): сейчас только у траков (ballast, sleeper).
## Закрытые модели видны, но серые и с пометкой (ModelAccess). Выбор отдаёт сигнал object_selected.

signal object_selected(setting: EntitySetting)

## Что показывает коллекция (порядок категорий). Terrain это инструменты, а не модели
const COLLECTION_CATEGORIES: Array[StringName] = [&"train", &"building", &"track", &"decor"]
const ALL: StringName = &"all"
const CLOSED_COLOR := Color(0.55, 0.55, 0.6)

var rules: LibraryRules
var profile: LibraryProfile

var _all: Array[EntitySetting] = []
var _by_key := {}          # key -> EntitySetting
var _titles := {}          # key -> название для списка (паспорт или имя)
var _infos := {}           # key -> ModelInfo или null
var _items := {}           # key -> TreeItem
var _order: Array[StringName] = []
var _search: LineEdit
var _cat: OptionButton
var _facet_box: VBoxContainer
var _facet_buttons := {}   # id признака -> OptionButton
var _count: Label
var _tree: Tree
var _selected_key: StringName = &""
var _silent := false
var _built := false


func _init(p_rules: LibraryRules = null, p_profile: LibraryProfile = null) -> void:
	rules = p_rules if p_rules != null else LibraryRules.make(LibraryRules.Source.SANDBOX, LibraryRules.Preset.STANDARD)
	profile = p_profile if p_profile != null else LibraryProfile.new()


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.text = "Каталог"
	add_child(head)

	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по названию"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_tree())
	add_child(_search)

	_cat = OptionButton.new()
	_cat.item_selected.connect(_on_category_changed)
	add_child(_cat)

	_facet_box = VBoxContainer.new()
	add_child(_facet_box)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_selected)
	add_child(_tree)

	_count = Label.new()
	_count.modulate = Color(1, 1, 1, 0.6)
	add_child(_count)

	_built = true
	reload()


# ==========================================
# ФИЛЬТР (чистая функция, тестируется отдельно)
# ==========================================

## Подходит ли объект: категория (ALL = любая), значения признаков {id: вариант}, подстрока в названии, имени или key
static func matches(s: EntitySetting, title: String, query: String, cat: StringName, wanted: Dictionary) -> bool:
	if cat != ALL and s.category != cat:
		return false
	for fid in wanted:
		if s.get_facet(fid) != str(wanted[fid]):
			return false
	var q := query.strip_edges().to_lower()
	if q != "":
		var hay := (title + " " + s.name + " " + String(s.get_key())).to_lower()
		if not hay.contains(q):
			return false
	return true


# ==========================================
# ПУБЛИЧНОЕ
# ==========================================

## Перечитать каталог с диска и перестроить список
func reload() -> void:
	_all.clear()
	_by_key.clear()
	_titles.clear()
	_infos.clear()
	for s in EntityCatalogProvider.load_all():
		if s.hide or not COLLECTION_CATEGORIES.has(s.category):
			continue
		var key := s.get_key()
		var info := ModelInfo.find(key)
		_all.append(s)
		_by_key[key] = s
		_infos[key] = info
		if info != null and info.title != "":
			_titles[key] = info.title
		elif s.name != "":
			_titles[key] = s.name
		else:
			_titles[key] = String(key)
	_rebuild_category_list()
	_rebuild_tree()


## Правила или профиль изменились: перекрасить замки, выбор сохраняется
func refresh_locks() -> void:
	_rebuild_tree()


func is_locked(key: StringName) -> bool:
	return not ModelAccess.is_open(rules, profile, key, _infos.get(key))


func setting_of(key: StringName) -> EntitySetting:
	return _by_key.get(key)


func info_of(key: StringName) -> ModelInfo:
	return _infos.get(key)


func total_count() -> int:
	return _all.size()


func visible_count() -> int:
	return _items.size()


func visible_keys() -> Array[StringName]:
	return _order.duplicate()


func first_visible_key() -> StringName:
	return _order[0] if not _order.is_empty() else &""


func current_category() -> StringName:
	if _cat == null or _cat.item_count == 0 or _cat.selected < 0:
		return ALL
	return _cat.get_item_metadata(_cat.selected)


## Значения включённых признаков: {id: вариант}
func facet_values() -> Dictionary:
	var out := {}
	for fid in _facet_buttons:
		var ob: OptionButton = _facet_buttons[fid]
		if ob.selected < 0:
			continue
		var v := str(ob.get_item_metadata(ob.selected))
		if v != "":
			out[fid] = v
	return out


func set_query(text: String) -> void:
	_search.text = text
	_rebuild_tree()


func set_category(cat: StringName) -> void:
	for i in _cat.item_count:
		if _cat.get_item_metadata(i) == cat:
			_cat.select(i)
			_on_category_changed(i)
			return


func set_facet(fid: StringName, option: String) -> void:
	if not _facet_buttons.has(fid):
		return
	var ob: OptionButton = _facet_buttons[fid]
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == option:
			ob.select(i)
			_rebuild_tree()
			return


## Выделить объект в списке. false, если его нет среди показанных (отфильтрован). emit: отдать object_selected
func select_key(key: StringName, emit := true) -> bool:
	if not _items.has(key):
		return false
	var it: TreeItem = _items[key]
	_silent = true
	it.select(0)
	_silent = false
	_tree.scroll_to_item(it)
	_selected_key = key
	if emit:
		object_selected.emit(_by_key[key])
	return true


# ==========================================
# ПОСТРОЕНИЕ
# ==========================================

func _rebuild_category_list() -> void:
	var keep := current_category()
	_cat.clear()
	_cat.add_item("Все категории")
	_cat.set_item_metadata(0, ALL)
	var present := {}
	for s in _all:
		present[s.category] = true
	for c in COLLECTION_CATEGORIES:
		if present.has(c):
			_cat.add_item(str(CatalogMeta.category_info(c)["name"]))
			_cat.set_item_metadata(_cat.item_count - 1, c)
	var idx := 0
	for i in _cat.item_count:
		if _cat.get_item_metadata(i) == keep:
			idx = i
	_cat.select(idx)
	_rebuild_facets()


func _rebuild_facets() -> void:
	for c in _facet_box.get_children():
		_facet_box.remove_child(c)
		c.queue_free()
	_facet_buttons.clear()
	var cat := current_category()
	if cat == ALL:
		return
	for spec in CatalogMeta.filter_specs(cat):
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = str(spec["title"])
		row.add_child(lab)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_item("Все")
		ob.set_item_metadata(0, "")
		for o in spec["options"]:
			ob.add_item(str(o["name"]))
			ob.set_item_metadata(ob.item_count - 1, str(o["id"]))
		ob.item_selected.connect(func(_i: int) -> void: _rebuild_tree())
		row.add_child(ob)
		_facet_box.add_child(row)
		_facet_buttons[spec["id"]] = ob


func _rebuild_tree() -> void:
	if not _built:
		return
	_tree.clear()
	_items.clear()
	_order.clear()
	var root := _tree.create_item()
	var cat_filter := current_category()
	var facets := facet_values()
	var query := _search.text
	# категория -> тег -> Array[EntitySetting]
	var by_cat := {}
	for s in _all:
		if not matches(s, _titles[s.get_key()], query, cat_filter, facets):
			continue
		if not by_cat.has(s.category):
			by_cat[s.category] = {}
		var tags: Dictionary = by_cat[s.category]
		if not tags.has(s.tag):
			tags[s.tag] = []
		(tags[s.tag] as Array).append(s)

	for cat in COLLECTION_CATEGORIES:
		if not by_cat.has(cat):
			continue
		var cat_item := _tree.create_item(root)
		cat_item.set_text(0, str(CatalogMeta.category_info(cat)["name"]))
		cat_item.set_selectable(0, false)
		var tags: Dictionary = by_cat[cat]
		for tag in CatalogMeta.sort_tags(cat, tags.keys()):
			var tag_item := _tree.create_item(cat_item)
			tag_item.set_text(0, str(tag))
			tag_item.set_selectable(0, false)
			var list: Array = tags[tag]
			list.sort_custom(_sort_objects)
			for s in list:
				var key: StringName = s.get_key()
				var it := _tree.create_item(tag_item)
				if is_locked(key):
					it.set_text(0, "%s  (закрыто)" % _titles[key])
					it.set_custom_color(0, CLOSED_COLOR)
				else:
					it.set_text(0, _titles[key])
				it.set_metadata(0, s)
				_items[key] = it
				_order.append(key)
	_count.text = "Показано %d из %d" % [_items.size(), _all.size()]
	if _selected_key != &"" and _items.has(_selected_key):
		_silent = true
		(_items[_selected_key] as TreeItem).select(0)
		_silent = false


static func _sort_objects(a: EntitySetting, b: EntitySetting) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.resource_path.get_file() < b.resource_path.get_file()


func _on_category_changed(_idx: int) -> void:
	_rebuild_facets()
	_rebuild_tree()


func _on_tree_selected() -> void:
	if _silent:
		return
	var it := _tree.get_selected()
	if it == null:
		return
	var s := it.get_metadata(0) as EntitySetting
	if s == null:
		return
	_selected_key = s.get_key()
	object_selected.emit(s)
