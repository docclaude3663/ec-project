extends RefCounted

########################
## Icon Studio: съёмка, коррекция и запись (ATTN_18 §18.3.5, шаги I5-I6)
########################
## Чистые функции над Image: ничего не знают про сцену. Кадр рисует studio_world.render_image().

const OUT_DIR := "res://core/library/icon_studio/icons/"
const FORMATS := ["png", "webp", "jpg"]


static func out_dir() -> String:
	return OUT_DIR


static func ensure_dir(dir: String) -> bool:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) in [OK, ERR_ALREADY_EXISTS]


## Крупный кадр -> результат: обрезка, Lanczos, края альфы, резкость
static func process(src: Image, t: Resource) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var out: Vector2i = t.output_size

	if t.trim_to_content and int(t.bg_mode) == 0:
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			var inner := Vector2(out) * (1.0 - 2.0 * float(t.padding))
			var k := minf(inner.x / r.size.x, inner.y / r.size.y)
			var sz := Vector2i(maxi(1, roundi(r.size.x * k)), maxi(1, roundi(r.size.y * k)))
			var piece := img.get_region(r)
			piece.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
			var canvas := Image.create(out.x, out.y, false, Image.FORMAT_RGBA8)
			canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, sz), (out - sz) / 2)
			img = canvas
	if img.get_size() != out:
		img.resize(out.x, out.y, Image.INTERPOLATE_LANCZOS)
	if int(t.bg_mode) == 0:
		img.fix_alpha_edges()
	if float(t.sharpen) > 0.001:
		_unsharp(img, float(t.sharpen))
	return img


## Нерезкая маска: размытие через уменьшение/увеличение, потом orig + k*(orig - blur) по RGB
static func _unsharp(img: Image, amount: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var blur := img.duplicate() as Image
	blur.resize(maxi(1, w / 2), maxi(1, h / 2), Image.INTERPOLATE_BILINEAR)
	blur.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var a := img.get_data()
	var b := blur.get_data()
	for i in range(0, a.size(), 4):
		for c in 3:
			a[i + c] = clampi(int(a[i + c] + amount * (a[i + c] - b[i + c])), 0, 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, a)


static func flatten(img: Image, bg: Color) -> Image:
	var f := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	f.fill(Color(bg, 1.0))
	f.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	f.convert(Image.FORMAT_RGB8)
	return f


## Выбранные в шаблоне форматы: индексы в FORMATS
static func selected_formats(t: Resource) -> Array:
	var a: Array = []
	if t.fmt_png:
		a.append(0)
	if t.fmt_webp:
		a.append(1)
	if t.fmt_jpg:
		a.append(2)
	return a


## fmt: 0 png, 1 webp, 2 jpg
static func save(img: Image, path: String, t: Resource, fmt: int, lossy: bool) -> Error:
	var g := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	match fmt:
		1:
			return img.save_webp(g, lossy, float(t.file_quality))
		2:
			return flatten(img, t.bg_color).save_jpg(g, float(t.file_quality))
		_:
			return img.save_png(g)


static func file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else -1


static func safe(s: String) -> String:
	var r := ""
	for ch in s:
		var letter := ch.to_lower() != ch.to_upper()
		r += ch if (letter or ch.is_valid_int() or ch == "-" or ch == "_") else "_"
	while r.contains("__"):
		r = r.replace("__", "_")
	return r.trim_prefix("_").trim_suffix("_")


static func make_name(pattern: String, s: EntitySetting, size: Vector2i) -> String:
	var n := pattern
	n = n.replace("{category}", safe(String(s.category)))
	n = n.replace("{tag}", safe(String(s.tag)))
	n = n.replace("{name}", safe(s.name))
	n = n.replace("{key}", safe(String(s.get_key())))
	n = n.replace("{size}", "%dx%d" % [size.x, size.y])
	n = safe(n)
	return n if n != "" else "icon"


## Свободное имя: если файл есть, добавляет _2, _3...
static func free_path(dir: String, base: String, ext: String) -> String:
	var p := dir + base + "." + ext
	var i := 2
	while FileAccess.file_exists(p):
		p = "%s%s_%d.%s" % [dir, base, i, ext]
		i += 1
	return p


# ==========================================
# SVG (сравнение, шаг I6)
# ==========================================

## Обёртка: PNG внутри SVG. Масштабируется, но остаётся растром
static func svg_wrapper(img: Image) -> String:
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	return '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%d" height="%d" viewBox="0 0 %d %d"><image width="%d" height="%d" xlink:href="data:image/png;base64,%s"/></svg>' % [
		img.get_width(), img.get_height(), img.get_width(), img.get_height(), img.get_width(), img.get_height(), b64]


## Векторизация «пикселями»: квантование до ~colors цветов, горизонтальные серии одного цвета -> rect.
## Это не трассировка контуров (она отложена), но честная оценка, во что выльется SVG из растра
static func svg_runs(img: Image, colors: int) -> String:
	var levels := maxi(2, ceili(pow(float(colors), 1.0 / 3.0)))
	var w := img.get_width()
	var h := img.get_height()
	var groups := {}   # цвет "rrggbb" -> Array строк rect
	for y in h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				x += 1
				continue
			var key := _quant(c, levels)
			var x2 := x + 1
			while x2 < w:
				var c2 := img.get_pixel(x2, y)
				if c2.a < 0.5 or _quant(c2, levels) != key:
					break
				x2 += 1
			if not groups.has(key):
				groups[key] = []
			groups[key].append("M%d %dh%dv1h-%dz" % [x, y, x2 - x, x2 - x])
			x = x2
	var out := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">' % [w, h, w, h]
	for key in groups:
		out += '<path fill="#%s" d="%s"/>' % [key, "".join(groups[key])]
	return out + "</svg>"


static func _quant(c: Color, levels: int) -> String:
	var m := float(levels - 1)
	var q := Color(roundf(c.r * m) / m, roundf(c.g * m) / m, roundf(c.b * m) / m)
	return q.to_html(false)
