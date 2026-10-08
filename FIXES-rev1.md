# LegionForge 7.3.5 (build 26124) — исправления rev.1

## 1. bnetserver: в списке миров «Archmage» и «НЕСОВМЕСТИМО»

**Причины (3 шт.):**

| # | Где | Что было | Почему ломало |
|---|-----|----------|---------------|
| 1 | `sql/10_archmage_realm.sql` | `UPDATE realmlist SET name='Archmage'` | при каждом `play.bat` мир переименовывался в Archmage |
| 2 | `sql/legionforge/auth/2018_04_06_00_auth.sql`, `sql/updates/auth/master/…`, `sql/base/auth_database.sql` | `realmlist.gamebuild = 26365` | клиент 7.3.5.**26124** ≠ 26365 → флаг `REALM_FLAG_VERSION_MISMATCH` → «Несовместимо», вход запрещён (`JoinRealm` → `ERROR_USER_SERVER_NOT_PERMITTED_ON_REALM`) |
| 3 | `core/src/server/shared/Realm/RealmList.cpp` (`GetBuildInfo`) | в таблице билдов не было ни одного билда 7.x | клиенту отдавалась версия мира **6.2.4** |

**Исправление:**
* `sql/10_archmage_realm.sql` → `sql/10_legionforge_realm.sql`: имя `LegionForge`, `gamebuild = 26124`, DEFAULT колонки 26124. Идемпотентно, применяется `setup.bat` и при каждом запуске `play.bat` — **уже существующая база исправится сама**.
* Апдейт 2018_04_06 и базовый дамп auth переведены на 26124.
* `RealmList.cpp`: добавлены билды 7.3.5 (25961…26972, включая 26124); фолбэк версии 6.2.4 → 7.3.5.
* `server_status.ps1`, `Motd` в конфигах: «Archmage» → «LegionForge».

## 2. worldserver закрывается сразу после баннера

```
Didn't find any executable MySQL binary at 'D:/legionforge_v.81026/server' or in path, correct the path in the *.conf ("MySQLExecutable").
Could not update the Login database, see log for details.
```

**Причины:**
* `MySQLExecutable = ""` в конфиге, а путь «из CMake» всегда был пустым: таргет `revision_data.h` вызывал `genrev.cmake` в режиме `cmake -P` **без** `-DMYSQL_EXECUTABLE`, и при каждой сборке `revision_data.h` перезаписывался с пустым путём.
* Портативный MySQL лежит в `tools\mysql\server\bin` и не находится в `PATH`.
* Отсутствие `mysql.exe` считалось фатальной ошибкой, хотя все SQL-патчи и так применяют `setup.bat`/`play.bat` (а `setup.bat` очищает `updates_include`, т.е. встроенному апдейтеру нечего применять).
* `SourceDirectory` указывал на `core\`, а папка `sql\` лежит в корне проекта.

**Исправление:**
* `core/src/server/database/Updater/DBUpdater.cpp` — поиск mysql: конфиг → CMake → PATH → `tools\mysql\server\bin` рядом с `server\` (до 4 уровней вверх) → `C:\Program Files\MySQL\*\bin`. Нет mysql или исходников → **предупреждение и продолжение запуска**, а не остановка. Автоопределение корня с `sql\`.
* Новый `patch_conf_paths.ps1` — прописывает `MySQLExecutable` и `SourceDirectory` в `worldserver.conf`/`bnetserver.conf`. Вызывается из `setup.bat` и при каждом `play.bat` (чинит уже существующие конфиги).
* `core/src/genrev/CMakeLists.txt` — в `genrev.cmake` теперь передаются `MYSQL_EXECUTABLE`, `GIT_EXECUTABLE`, `WITHOUT_GIT`.
* `play.bat` — окна bnetserver/worldserver при аварийном завершении больше не закрываются (`|| pause`), ошибку видно.
* `core/src/server/worldserver/worldserver.conf.dist` синхронизирован с `server/worldserver.conf.dist` (в ядре оставались порт 8095 и база `legion_characters` с чужого ПК).

## 3. «LEGIONFORGE rev. unknown 1970-01-01 00:00:00 +0000 (Archived branch)»

Сборка идёт с `-DWITHOUT_GIT=1`, а `genrev.cmake` в этом случае жёстко подставлял `unknown / 1970-01-01 / Archived`.

Теперь (`core/cmake/genrev.cmake`, `core/revision_data.h.in.cmake`, `core/src/common/GitRevision.cpp`):

```
LEGIONFORGE rev.1 2026-10-09 14:22:31 (Legion 7.3.5.26124, Win64, Release, Static) (worldserver-daemon)
```

* номер ревизии — из `core/revision.txt` (сейчас `1`; увеличивайте вручную к каждому релизу) или `-DLEGIONFORGE_REVISION=N`;
* дата/время — реальное локальное время сборки (обновляется при каждой сборке);
* в свойствах .exe: версия файла `7.3.5.1`, копирайт `(c)2008-2026 LegionForge`.

## 4. Баннер TrinityCore → LegionForge

`core/src/common/Banner.cpp` — ASCII-арт «LegionForge» тем же шрифтом (larry3d), строка `L E G I O N 7.3.5 (build 26124)` и `https://legionforge.ru`. Ширина 79 символов — помещается в консоль 80 колонок. Используется и bnetserver, и worldserver.

## Что нужно сделать после обновления

1. Распаковать поверх (или в новую папку) и запустить `UNBLOCK.bat`.
2. **Пересобрать** сервер: `build_server.bat` (или `setup.bat`) — исправления ядра попадают в exe только после компиляции.
3. Запустить `play.bat` — он сам исправит realm в базе и пути в конфигах.
