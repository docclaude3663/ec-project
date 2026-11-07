extends RefCounted

########################
## Icon Studio: встроенные и пользовательские шаблоны (ATTN_18 §18.3.3, шаг I6)
########################
## Встроенные: заготовки по категориям объектов. Свои: user://icon_studio/templates/<id>.tres

const Template := preload("res://core/library/icon_studio/icon_template.gd")
const USER_DIR := "user://icon_studio/templates/"

## Категория EntitySetting -> id встроенного шаблона («авто по категории»)
const BY_CATEGORY := {
	&"train": &"wagon",
	&"track": &"track",
	&"building": &"building",
	&"terrain": &"terrain",
}


static func builtin_ids() -> Array:
	return [&"wagon", &"track", &"building", &"terrain"]


static func make_builtin(id: StringName) -> Template:
	var t := Template.new()
	t.id = id
	var slots: Array = []
	match id:
		&"wagon":
			t.title = "Вагон, 3/4 сверху"
			slots = [[35.0, -22.0, false], [90.0, 0.0, false], [0.0, 0.0, false], [35.0, -89.0, false], [90.0, 0.0, true], [-35.0, -22.0, false]]
		&"track":
			t.title = "Трек, сверху под углом"
			slots = [[35.0, -50.0, false], [0.0, -89.0, true], [90.0, 0.0, false], [0.0, 0.0, false], [35.0, -25.0, false], [-35.0, -50.0, false]]
			t.fit_margin = 0.05
			t.trim_to_content = true
			t.bg_mode = 0
		&"building":
			t.title = "Здание, 3/4"
			slots = [[35.0, -20.0, false], [90.0, 0.0, false], [0.0, 0.0, false], [35.0, -89.0, false], [-35.0, -20.0, false], [180.0, -20.0, false]]
		_:
			t.title = "Рельеф, ортогональный сверху"
			slots = [[0.0, -89.0, true], [35.0, -35.0, false], [90.0, 0.0, true], [0.0, 0.0, true], [35.0, -25.0, false], [-35.0, -35.0, false]]
			t.bg_mode = 1
	var a: Array = []
	for v in slots:
		a.append({"yaw": v[0], "pitch": v[1], "ortho": v[2], "fov": 30.0, "zoom": 1.0, "pivot": Vector3.ZERO})
	t.slots = a
	return t


## Все доступные: [{id, title, builtin}]
static func list_all() -> Array:
	var out: Array = []
	for id in builtin_ids():
		out.append({"id": id, "title": make_builtin(id).title, "builtin": true})
	for f in DirAccess.get_files_at(USER_DIR):
		if f.ends_with(".tres"):
			var t := load(USER_DIR + f)
			if t != null and t.get_script() == Template:
				out.append({"id": StringName(f.get_basename()), "title": String(t.title), "builtin": false})
	return out


static func load_template(id: StringName) -> Template:
	if id in builtin_ids():
		return make_builtin(id)
	var p := USER_DIR + String(id) + ".tres"
	if not FileAccess.file_exists(p):
		return null
	return ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as Template


static func save_user(t: Template, title: String) -> StringName:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var id := StringName(String(title).to_lower().validate_filename().replace(" ", "_"))
	if id == &"" or id in builtin_ids():
		id = StringName("custom_" + str(Time.get_ticks_msec()))
	var c := Template.new()
	c.from_dict(t.to_dict())
	c.id = id
	c.title = title
	ResourceSaver.save(c, USER_DIR + String(id) + ".tres")
	return id


static func delete_user(id: StringName) -> void:
	if id in builtin_ids():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + String(id) + ".tres"))
