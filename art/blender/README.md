# art/blender

Исходники моделей: `<id>.blend`. Папка `art/` содержит пустой `.gdignore`, Godot её не видит и ничего отсюда не импортирует.

- Экспорт идёт скриптом `tools/blender/ec_model_tools.py` (вкладка EC) в `data/models/<id>/<id>.glb`, шпаргалка `tools/blender/CHEATSHEET.md`.
- Большие `.blend` лучше держать вне git или в Git LFS; резервные `*.blend1` игнорируются.

У автора исходники `.blend` лежат вне репозитория: `E:\GodotCopy\Blender\Art\`; панель EC экспортирует в `D:\Godot\ec-project\data\models\<id>\` (поле «Папка моделей»). Эта папка нужна, только если `.blend` захочется держать в репозитории.
