# data/models

Новые модели, по одной папке на модель: `data/models/<вид>/<id>/` (`trains`, `buildings`).

```
data/models/trains/wagon_04/
  wagon_04.glb (+ .import)   экспорт из Blender, имя постоянное
  wagon_04.tscn              сцена-обёртка: RigidBody3D + инстанс .glb + коллизия
  tex/                       внешние текстуры, если не вшиты в .glb
```

Правила переходного периода (см. `0_ATTN_24_model_pipeline.md` §24.12):

- Объекты каталога остаются на старых местах: `data/<категория>/objects/<id>.tres`. Каталог читает только эти папки и без рекурсии, пути записаны в сейвах.
- Паспорта остаются в `data/library/info/`.
- Старые модели (`data/import/`, `data/trains/*.tscn`, `data/buildings/*.tscn`) пока не трогаем. Переезд по одной модели в панели FileSystem Godot, отдельным коммитом; когда в старых папках ничего не останется, чистим.
