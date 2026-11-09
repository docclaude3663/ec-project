extends RefCounted

# XX claude-library (новый файл)
########################
## Карта позиций и нормалей в развёртке UV2 (C2.0, ATTN_22 §22.7.2.1)
########################
## На CPU растеризует треугольники меша в сетку res x res по UV2 и пишет в каждый тексель позицию и нормаль
## точки меша (локальные координаты). Float32, без tone mapping и без потерь точности, как у рендера в SubViewport.
## Тексели вокруг островов добиваются на 2 пикселя (dilation), чтобы шов не светился при билинейной фильтрации.
## Возвращает {ok, pos_img, nrm_img, tris, covered, dilated, overlapped, skipped, ms, error}.

const DILATE_PASSES := 2
const EDGE_EPS := 0.0001     ## допуск «внутри» для треугольника: закрывает щели на общих рёбрах
const INNER_EPS := 0.001     ## «строго внутри» для подсчёта перекрытий


static func bake(mesh: Mesh, res: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var n := res * res
	var pos := PackedFloat32Array()
	pos.resize(n * 4)
	var nrm := PackedFloat32Array()
	nrm.resize(n * 4)
	var own := PackedInt32Array()       # -1 пусто, -2 добавлен dilation, иначе номер треугольника
	own.resize(n)
	own.fill(-1)
	var inner := PackedByteArray()      # 1: тексель строго внутри треугольника-владельца
	inner.resize(n)
	var tris := 0
	var covered := 0
	var overlapped := 0
	var skipped := 0

	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts_v: Variant = arrays[Mesh.ARRAY_VERTEX]
		var uv2_v: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		if not (verts_v is PackedVector3Array) or not (uv2_v is PackedVector2Array) or (uv2_v as PackedVector2Array).is_empty():
			skipped += 1
			continue
		var vs: PackedVector3Array = verts_v
		var us: PackedVector2Array = uv2_v
		var norms_v: Variant = arrays[Mesh.ARRAY_NORMAL]
		var ns := PackedVector3Array()
		if norms_v is PackedVector3Array:
			ns = norms_v
		var has_n := ns.size() == vs.size()
		var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var order := PackedInt32Array()
		if idx_v is PackedInt32Array and not (idx_v as PackedInt32Array).is_empty():
			order = idx_v
		else:
			order = PackedInt32Array(range(vs.size()))

		for t in range(0, order.size() - 2, 3):
			var ia := order[t]
			var ib := order[t + 1]
			var ic := order[t + 2]
			var a := us[ia]
			var b := us[ib]
			var c := us[ic]
			tris += 1
			var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
			if absf(d) < 1e-14:
				continue
			var pa := vs[ia]
			var pb := vs[ib]
			var pc := vs[ic]
			var na := Vector3.UP
			var nb := Vector3.UP
			var nc := Vector3.UP
			if has_n:
				na = ns[ia]
				nb = ns[ib]
				nc = ns[ic]
			else:
				var fn := (pb - pa).cross(pc - pa).normalized()
				na = fn
				nb = fn
				nc = fn
			var x0 := clampi(int(floor(minf(a.x, minf(b.x, c.x)) * res)), 0, res - 1)
			var x1 := clampi(int(ceil(maxf(a.x, maxf(b.x, c.x)) * res)), 0, res - 1)
			var y0 := clampi(int(floor(minf(a.y, minf(b.y, c.y)) * res)), 0, res - 1)
			var y1 := clampi(int(ceil(maxf(a.y, maxf(b.y, c.y)) * res)), 0, res - 1)
			for y in range(y0, y1 + 1):
				var py := (y + 0.5) / res
				for x in range(x0, x1 + 1):
					var px := (x + 0.5) / res
					var w0 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
					var w1 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
					var w2 := 1.0 - w0 - w1
					if w0 < -EDGE_EPS or w1 < -EDGE_EPS or w2 < -EDGE_EPS:
						continue
					var is_inner := 1 if (w0 > INNER_EPS and w1 > INNER_EPS and w2 > INNER_EPS) else 0
					var i := y * res + x
					if own[i] != -1:
						if is_inner == 1 and inner[i] == 1:
							overlapped += 1
							continue
						if not (is_inner == 1 and inner[i] == 0):
							continue
					else:
						covered += 1
					own[i] = tri_id_of(tris)
					inner[i] = is_inner
					var p := pa * w0 + pb * w1 + pc * w2
					var nn := (na * w0 + nb * w1 + nc * w2).normalized()
					var o := i * 4
					pos[o] = p.x
					pos[o + 1] = p.y
					pos[o + 2] = p.z
					pos[o + 3] = 1.0
					nrm[o] = nn.x
					nrm[o + 1] = nn.y
					nrm[o + 2] = nn.z
					nrm[o + 3] = 1.0

	# dilation: пустой тексель рядом с покрытым копирует его позицию и нормаль
	var dilated := 0
	for pass_i in DILATE_PASSES:
		var prev := own.duplicate()
		for y in res:
			for x in res:
				var i := y * res + x
				if prev[i] != -1:
					continue
				var src := -1
				if x > 0 and prev[i - 1] != -1:
					src = i - 1
				elif x < res - 1 and prev[i + 1] != -1:
					src = i + 1
				elif y > 0 and prev[i - res] != -1:
					src = i - res
				elif y < res - 1 and prev[i + res] != -1:
					src = i + res
				if src >= 0:
					for k in 4:
						pos[i * 4 + k] = pos[src * 4 + k]
						nrm[i * 4 + k] = nrm[src * 4 + k]
					own[i] = -2
					dilated += 1

	var out := {
		"ok": covered > 0, "tris": tris, "covered": covered, "dilated": dilated,
		"overlapped": overlapped, "skipped": skipped, "res": res,
		"ms": Time.get_ticks_msec() - t0, "error": "",
	}
	if covered == 0:
		out["error"] = "ни одного покрытого текселя: нет UV2 или все треугольники вырождены"
		return out
	out["pos_img"] = Image.create_from_data(res, res, false, Image.FORMAT_RGBAF, pos.to_byte_array())
	out["nrm_img"] = Image.create_from_data(res, res, false, Image.FORMAT_RGBAF, nrm.to_byte_array())
	return out


## Номер владельца тексселя: просто номер треугольника (нужен только как «не -1 и не -2»)
static func tri_id_of(tri_count: int) -> int:
	return tri_count
