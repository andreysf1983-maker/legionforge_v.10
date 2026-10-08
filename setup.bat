@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::   LEGIONFORGE 7.3.5 — Однопользовательская установка сервера
::   Файл: setup.bat   (запускать ОТ ИМЕНИ АДМИНИСТРАТОРА)
::
::   Порядок работы:
::     1. Проверка прав администратора
::     2. Подготовка и запуск portable MySQL при необходимости
::     3. Поиск клиента WoW 7.3.5
::     4. Программы сервера: готовый архив или АВТОКОМПИЛЯЦИЯ build_server.bat
::        Загрузка дампов ADB_735.10 с релиза AshamaneCore: get_databases.ps1
::     5. Создание баз и импорт схем
::     6. Применение кастомных SQL-патчей LEGIONFORGE
::     7. Генерация конфигураций worldserver.conf / bnetserver.conf
::     8. Извлечение игровых данных (maps / vmaps / mmaps)
::     9. Создание учётной записи администратора
::
::   Все подсказки выведены на русском языке.
::   Кодировка файла: UTF-8 без BOM, кодовая страница 65001.
:: ============================================================

:: ---- Источники дополнительных игровых архивов ----
:: В текущем публичном репозитории нет опубликованных бинарников/дампов.
:: Можно положить ZIP-файлы в setup_tmp или задать эти переменные окружения.
set "BINARIES_URL=%LEGIONFORGE_BINARIES_URL%"
set "DATABASES_URL=%LEGIONFORGE_DATABASES_URL%"

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SERVER_DIR=%ROOT%\server"
set "TMP_DIR=%ROOT%\setup_tmp"
set "SQL_DIR=%ROOT%\sql"
set "LOG_FILE=%ROOT%\setup_log.txt"
set "MYSQL_CNF=%ROOT%\setup_tmp\mysql.cnf"

title LEGIONFORGE 7.3.5 - Установка сервера
color 0A

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5 — установка сервера
echo  =========================================================
echo.

:: ---- 1. Проверка прав администратора ----
net session >nul 2>&1
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Для работы скрипта требуются права администратора.
    echo      Нажмите правой кнопкой на setup.bat и выберите
    echo      "Запуск от имени администратора".
    echo.
    pause
    exit /b 1
)

echo  [*] Проверка пройдена: права администратора получены.
echo  [%date% %time%] Установка начата > "%LOG_FILE%"

:: ---- 2. Подготовка MySQL до установки игровых данных ----
echo.
echo  [*] Проверка и запуск MySQL на порту 3306...
set "MYSQL="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_mysql.ps1" -Port 3306 -EnsureRunning 2^>nul`) do set "MYSQL=%%P"
if not defined MYSQL (
    echo  [*] MySQL не найден. Подготовка переносимой версии в tools\mysql...
    call "%ROOT%\upload_tools.bat" /prepare-only
    if errorlevel 1 goto :SETUP_FAIL
    set "MYSQL="
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_mysql.ps1" -Port 3306 -EnsureRunning 2^>nul`) do set "MYSQL=%%P"
)
if not defined MYSQL (
    echo  [ВНИМАНИЕ] Не удалось подготовить MySQL. Смотрите tools\mysql\logs\mysql-error.log
    goto :SETUP_FAIL
)
if not exist "%MYSQL%" (
    echo  [ВНИМАНИЕ] mysql.exe не найден: %MYSQL%
    goto :SETUP_FAIL
)
echo  [OK] MySQL готов: %MYSQL%

:: ---- 3. Поиск клиента WoW 7.3.5 ----
echo.
echo  [*] Поиск клиента World of Warcraft 7.3.5...

set "CLIENT_EXE="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_client.ps1" -Root "%ROOT%" -SavedPathFile "%ROOT%\client_path.txt"`) do set "CLIENT_EXE=%%P"

if "!CLIENT_EXE!"=="" (
    echo  [ВНИМАНИЕ] Клиент не найден в папке WoW_Client и рядом со скриптом.
    echo      Введите полный путь к папке или файлу клиента 7.3.5.
    echo      Примеры:
    echo        D:\Games\Legion\Wow-64.exe
    echo        C:\WoW_735
    set /p "CLIENT_INPUT=  Путь: "
    if defined CLIENT_INPUT (
        for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_client.ps1" -Root "!CLIENT_INPUT!"`) do set "CLIENT_EXE=%%P"
        if "!CLIENT_EXE!"=="" if exist "!CLIENT_INPUT!" set "CLIENT_EXE=!CLIENT_INPUT!"
    )
)

if "!CLIENT_EXE!"=="" (
    echo  [ВНИМАНИЕ] Клиент так и не найден. Установка остановлена.
    echo      Поместите клиент 7.3.5 в папку: %ROOT%\WoW_Client
    echo      или запустите setup.bat повторно и укажите путь к Wow-64.exe.
    echo.
    pause
    exit /b 1
)

for %%I in ("!CLIENT_EXE!") do set "CLIENT_DIR=%%~dpI"
set "CLIENT_DIR=!CLIENT_DIR:~0,-1!"
> "%ROOT%\client_path.txt" echo !CLIENT_EXE!
echo  [OK] Клиент найден: !CLIENT_EXE!
echo  [%date% %time%] Клиент: !CLIENT_EXE! >> "%LOG_FILE%"

:: ---- 4. Проверка подготовленного MySQL ----
echo.
echo  [*] Проверка MySQL...
if not exist "%MYSQL%" (
    echo  [ВНИМАНИЕ] Не найден mysql.exe: %MYSQL%
    goto :SETUP_FAIL
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_mysql.ps1" -Port 3306 -EnsureRunning >nul 2>&1
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Сервер MySQL не отвечает на порту 3306.
    goto :SETUP_FAIL
)
echo  [OK] MySQL работает: %MYSQL%

:: ---- 5. Доступ администратора MySQL ----
echo.
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"
set "MYSQL_CNF=%TMP_DIR%\mysql.cnf"
if exist "%MYSQL_CNF%" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action Test -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >nul 2>&1
    if not errorlevel 1 (
        echo  [OK] Сохранённая учётная запись MySQL проверена.
        goto :MYSQL_AUTH_OK
    )
)

echo  [*] Введите данные администратора уже установленного MySQL.
setlocal DisableDelayedExpansion
set /p "MYSQL_PASS=  Пароль root (Enter, если пароля нет): "
(
  echo [client]
  echo user=root
  echo password=%MYSQL_PASS%
  echo host=127.0.0.1
  echo port=3306
  echo protocol=tcp
) > "%MYSQL_CNF%"
endlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action Test -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >nul 2>&1
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Не удалось подключиться к MySQL с указанным паролем.
    echo      Проверьте, что MySQL запущен и слушает порт 3306.
    goto :SETUP_FAIL
)

:MYSQL_AUTH_OK
echo  [OK] Подключение к MySQL успешно.

:: ---- Совместимость и настройка MySQL ----
echo.
echo  [*] Применение патча совместимости MySQL 8.x...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action CompatFix -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >nul 2>&1
echo  [*] Настройка производительности MySQL...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action Tune -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >nul 2>&1
echo  [OK] MySQL настроен.

:: ---- 6. Программы сервера: готовый архив ИЛИ автоматическая компиляция ----
echo.
echo  [*] Проверка программ сервера: worldserver, bnetserver, утилиты карт...
set "NEED_BUILD="
if not exist "%SERVER_DIR%\worldserver.exe" set "NEED_BUILD=1"
if not exist "%SERVER_DIR%\bnetserver.exe" set "NEED_BUILD=1"
if not exist "%SERVER_DIR%\mapextractor.exe" set "NEED_BUILD=1"
if not defined NEED_BUILD goto :BINARIES_READY

if not exist "%TMP_DIR%\server_binaries.zip" if exist "%ROOT%\server_binaries.zip" copy /Y "%ROOT%\server_binaries.zip" "%TMP_DIR%\server_binaries.zip" >nul
if not exist "%TMP_DIR%\server_binaries.zip" if defined BINARIES_URL (
    echo  [*] Загрузка готовых программ сервера по LEGIONFORGE_BINARIES_URL...
    curl.exe --fail --location --retry 3 --retry-delay 2 --output "%TMP_DIR%\server_binaries.zip" "%BINARIES_URL%" --show-error
    if errorlevel 1 (
        echo  [ВНИМАНИЕ] Загрузка не удалась - сервер будет скомпилирован из исходников.
        del /q "%TMP_DIR%\server_binaries.zip" >nul 2>&1
    )
)
if exist "%TMP_DIR%\server_binaries.zip" (
    echo  [*] Распаковка готового архива server_binaries.zip...
    if not exist "%SERVER_DIR%" mkdir "%SERVER_DIR%"
    set "LF_ARCHIVE=%TMP_DIR%\server_binaries.zip"
    set "LF_DEST=%SERVER_DIR%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:LF_ARCHIVE -DestinationPath $env:LF_DEST -Force"
    if errorlevel 1 echo  [ВНИМАНИЕ] Архив повреждён - сервер будет скомпилирован из исходников.
    set "LF_ARCHIVE="
    set "LF_DEST="
)
if exist "%SERVER_DIR%\worldserver.exe" if exist "%SERVER_DIR%\bnetserver.exe" if exist "%SERVER_DIR%\mapextractor.exe" goto :BINARIES_READY

echo.
echo  [*] Готовых программ сервера нет - запускается АВТОМАТИЧЕСКАЯ КОМПИЛЯЦИЯ.
echo      Всё нужное скачается в tools\ само: 7-Zip, CMake, Boost, OpenSSL и
echo      официальный компилятор Microsoft - Visual Studio 2022 Build Tools.
echo      Первый раз это занимает 1-2 часа. Если прервётся - запустите
echo      setup.bat снова: уже скачанное повторно не загружается.
echo  [%date% %time%] Запуск build_server.bat >> "%LOG_FILE%"
call "%ROOT%\build_server.bat" /auto
if errorlevel 1 (
    echo  [ОШИБКА] Компиляция сервера не удалась. Журнал: %ROOT%\build_log.txt
    goto :SETUP_FAIL
)

:BINARIES_READY
if not exist "%SERVER_DIR%\worldserver.exe" (
    echo  [ОШИБКА] worldserver.exe не найден в папке server.
    goto :SETUP_FAIL
)
if not exist "%SERVER_DIR%\bnetserver.exe" (
    echo  [ОШИБКА] bnetserver.exe не найден в папке server.
    goto :SETUP_FAIL
)
echo  [OK] Программы сервера готовы.

:: ---- 7. Полные дампы игрового мира ADB_735.10 ----
:: get_databases.ps1 ищет setup_tmp\*.sql, databases.zip, ADB_735.10.rar, LEGIONFORGE_DATABASES_URL,
:: а если ничего нет - скачивает официальный релиз AshamaneCore ADB_735.10 с проверкой SHA-256.
echo.
echo  [*] Подготовка дампов базы мира ADB_735.10: world + hotfix...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\get_databases.ps1" -TargetDir "%TMP_DIR%"
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось получить ADB_735.10_world.sql / ADB_735.10_hotfix.sql.
    echo           Скачайте вручную ADB_735.10.rar со страницы
    echo           https://github.com/AshamaneProject/AshamaneCore/releases/tag/ADB_735.10
    echo           положите его в папку setup_tmp и запустите setup.bat снова.
    goto :SETUP_FAIL
)
:DATABASES_READY
echo  [OK] Дампы world и hotfix найдены.

:: ---- 7. Создание баз данных ----
echo.
echo  [*] Создание баз данных auth / characters / world / hotfixes...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "CREATE DATABASE IF NOT EXISTS auth CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS characters CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS world CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS hotfixes CHARACTER SET utf8mb4;"
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Не удалось создать базы данных.
    goto :SETUP_FAIL
)
echo  [OK] Базы данных созданы.
echo  [*] Создание MySQL-пользователя admin@legionforge.ru...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action EnsureAppUser -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Не удалось создать пользователя MySQL admin@legionforge.ru.
    echo      Подробности: %LOG_FILE%
    goto :SETUP_FAIL
)
echo  [OK] Пользователь MySQL admin@legionforge.ru настроен.

echo  [*] Базовые схемы auth / characters - только в ПУСТЫЕ базы, данные игроков не затираются...
if not exist "%SQL_DIR%\base\auth_database.sql" (
    echo  [ВНИМАНИЕ] Не найдена схема %SQL_DIR%\base\auth_database.sql
    goto :SETUP_FAIL
)
if not exist "%SQL_DIR%\base\characters_database.sql" (
    echo  [ВНИМАНИЕ] Не найдена схема %SQL_DIR%\base\characters_database.sql
    goto :SETUP_FAIL
)
if not exist "%SQL_DIR%\base\dev\hotfixes_database.sql" (
    echo  [ВНИМАНИЕ] Не найдена схема hotfixes_database.sql
    goto :SETUP_FAIL
)
call :IMPORT_IF_EMPTY auth "%SQL_DIR%\base\auth_database.sql"
if errorlevel 1 goto :SETUP_FAIL
call :IMPORT_IF_EMPTY characters "%SQL_DIR%\base\characters_database.sql"
if errorlevel 1 goto :SETUP_FAIL
echo  [*] Обновления схем auth / characters (без них worldserver не откроет базу персонажей)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\apply_schema_updates.ps1" -Database auth -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 goto :SETUP_FAIL
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\apply_schema_updates.ps1" -Database characters -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 goto :SETUP_FAIL
echo  [OK] Базовые схемы импортированы и обновлены.

:: ---- 8. Импорт игровой базы данных ----
if exist "%TMP_DIR%\world_imported.flag" (
    echo.
    echo  [OK] Базы world и hotfixes уже импортированы ранее - пропуск.
    echo       Для полного переимпорта удалите файл setup_tmp\world_imported.flag
    goto :WORLD_IMPORTED
)
echo.
echo  [*] Схема hotfixes...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" hotfixes < "%SQL_DIR%\base\dev\hotfixes_database.sql" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось импортировать схему hotfixes. Подробности: %LOG_FILE%
    goto :SETUP_FAIL
)
echo.
echo  [*] Импорт world-базы (около 350 МБ), 3-8 минут...
cmd /c ""%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M world < "%TMP_DIR%\ADB_735.10_world.sql""
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Импорт world-базы завершился с ошибкой.
    goto :SETUP_FAIL
)
echo  [OK] World-база импортирована.

echo.
echo  [*] Импорт hotfix-базы (около 120 МБ)...
cmd /c ""%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M hotfixes < "%TMP_DIR%\ADB_735.10_hotfix.sql""
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Импорт hotfix-базы завершился с ошибкой.
    goto :SETUP_FAIL
)
echo  [OK] Hotfix-база импортирована.
> "%TMP_DIR%\world_imported.flag" echo %date% %time%
:WORLD_IMPORTED

:: ---- 9. Кастомные SQL-патчи LEGIONFORGE ----
echo.
echo  [*] Применение кастомных SQL-патчей LEGIONFORGE...

call :APPLY characters "%SQL_DIR%\31_remove_bots_characters.sql"
call :APPLY world      "%SQL_DIR%\31_remove_bots_world.sql"
call :APPLY world      "%SQL_DIR%\02_custom_creatures.sql"
call :APPLY hotfixes   "%SQL_DIR%\03_hotfix_column_patches.sql"
call :APPLY characters "%SQL_DIR%\04_fix_instance_data.sql"
call :APPLY world      "%SQL_DIR%\05_legion_game_tele.sql"
call :APPLY world      "%SQL_DIR%\07_legion_instance_template.sql"
call :APPLY world      "%SQL_DIR%\08_all_instance_template.sql"
call :APPLY world      "%SQL_DIR%\09_lfg_dungeon_entrances.sql"
call :APPLY auth       "%SQL_DIR%\10_legionforge_realm.sql"

echo  [*] Применение модульных патчей LEGIONFORGE (40-49)...
call :APPLY hotfixes   "%SQL_DIR%\40_legionforge_items.sql"
call :APPLY world      "%SQL_DIR%\40_legionforge_items.sql"
call :APPLY world      "%SQL_DIR%\41_legionforge_minibosses.sql"
call :APPLY world      "%SQL_DIR%\42_legionforge_miniboss_loot.sql"
call :APPLY hotfixes   "%SQL_DIR%\43_legionforge_upgrade_tokens.sql"
call :APPLY world      "%SQL_DIR%\43_legionforge_upgrade_tokens.sql"
call :APPLY world      "%SQL_DIR%\44_legionforge_upgrade_limits.sql"
call :APPLY hotfixes   "%SQL_DIR%\44_legionforge_upgrade_limits.sql"
call :APPLY world      "%SQL_DIR%\45_legionforge_ancient_knowledge.sql"
call :APPLY world      "%SQL_DIR%\46_legionforge_playerbots.sql"
call :APPLY auth       "%SQL_DIR%\46_legionforge_playerbots.sql"
call :APPLY characters "%SQL_DIR%\46_legionforge_playerbots.sql"
call :APPLY auth       "%SQL_DIR%\32_playerbot_auth.sql"
call :APPLY auth       "%SQL_DIR%\32_playerbot_names.sql"
call :APPLY world      "%SQL_DIR%\32_playerbot_world.sql"
call :APPLY auth       "%SQL_DIR%\47_legionforge_admin.sql"

echo  [*] Применение остальных SQL-патчей...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\apply_play_sql.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Часть SQL-патчей завершилась с ошибкой, подробности выше.
) else (
    echo  [OK] SQL-патчи применены.
)

echo  [*] Сброс журнала обновлений баз данных...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" world -e "TRUNCATE TABLE updates; TRUNCATE TABLE updates_include;" >nul 2>&1
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" hotfixes -e "TRUNCATE TABLE updates; TRUNCATE TABLE updates_include;" >nul 2>&1
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" auth -e "TRUNCATE TABLE updates; TRUNCATE TABLE updates_include;" >nul 2>&1
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" characters -e "TRUNCATE TABLE updates; TRUNCATE TABLE updates_include;" >nul 2>&1

:: ---- 10. Конфигурация сервера ----
echo.
echo  [*] Настройка worldserver.conf...
if not exist "%SERVER_DIR%\worldserver.conf" (
    if exist "%SERVER_DIR%\worldserver.conf.dist" (
        copy "%SERVER_DIR%\worldserver.conf.dist" "%SERVER_DIR%\worldserver.conf" >nul
    ) else (
        echo  [ВНИМАНИЕ] Не найден worldserver.conf.dist
        goto :SETUP_FAIL
    )
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action PatchConf -ConfPath "%SERVER_DIR%\worldserver.conf" -ConfKeys LoginDatabaseInfo,WorldDatabaseInfo,CharacterDatabaseInfo,HotfixDatabaseInfo -CnfPath "%MYSQL_CNF%"
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Не удалось прописать параметры подключения в worldserver.conf
    goto :SETUP_FAIL
)
echo  [OK] worldserver.conf настроен.

echo  [*] Настройка bnetserver.conf...
if not exist "%SERVER_DIR%\bnetserver.conf" (
    if exist "%SERVER_DIR%\bnetserver.conf.dist" (
        copy "%SERVER_DIR%\bnetserver.conf.dist" "%SERVER_DIR%\bnetserver.conf" >nul
    )
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\mysql_helper.ps1" -Action PatchConf -ConfPath "%SERVER_DIR%\bnetserver.conf" -ConfKeys LoginDatabaseInfo -CnfPath "%MYSQL_CNF%"
echo  [OK] bnetserver.conf настроен.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\patch_conf_paths.ps1" -Root "%ROOT%" -MysqlExe "%MYSQL%"

if not exist "%SERVER_DIR%\data" mkdir "%SERVER_DIR%\data"

:: ---- 11. Извлечение игровых данных ----
echo.
echo  [*] Извлечение игровых данных (maps / vmaps / mmaps) из клиента...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\extract_maps.ps1" -ClientDir "!CLIENT_DIR!" -ServerDir "%SERVER_DIR%" -MmapsMode prompt
if errorlevel 1 (
    echo  [ВНИМАНИЕ] Извлечение игровых данных завершилось с ошибкой.
    echo      Без maps/vmaps сервер не запустится. Запустите extract_maps.bat повторно.
    goto :SETUP_FAIL
)
echo  [OK] Игровые данные извлечены.

:: ---- 12. Учётная запись администратора ----
echo.
echo  [*] Создание учётной записи администратора LEGIONFORGE...
echo      Логин:    admin@legionforge.ru
echo      Пароль:   legionforge
set "ADMIN_OK="
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\update_local_account.ps1" -Username "admin" -Password "legionforge" -Email "admin@legionforge.ru" -GmLevel 3 -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if not errorlevel 1 set "ADMIN_OK=1"
if not defined ADMIN_OK (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\create_local_account.ps1" -Username "admin" -Password "legionforge" -Email "admin@legionforge.ru" -GmLevel 3 -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
    if not errorlevel 1 set "ADMIN_OK=1"
)
if defined ADMIN_OK (
    echo  [OK] Учётная запись администратора готова.
) else (
    echo  [ВНИМАНИЕ] Не удалось создать учётную запись администратора.
    echo      Создайте её вручную командой: create_admin.bat
)

:: ---- 13. Патч клиента ----
echo.
echo  [*] Патч клиента (привязка к локальному серверу)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\patch_client.ps1" -ClientDir "!CLIENT_DIR!"
echo  [OK] Клиент обработан.

echo.
echo  =========================================================
echo   Установка LEGIONFORGE завершена успешно.
echo  =========================================================
echo.
echo   Следующие шаги:
echo     1. Запустите play.bat      - запуск сервера и клиента
echo     2. Войдите в игру:         admin@legionforge.ru
echo     3. Пароль администратора:  legionforge
echo.
echo   Полезные файлы:
echo     build_worldserver.bat  - пересборка ядра после правок C++
echo     create_admin.bat       - повторное создание администратора
echo     server_status.bat      - состояние сервера и баз данных
echo.
echo   Журнал установки: %LOG_FILE%
echo.
pause
exit /b 0

:: ============================================================
::  Служебная подпрограмма: применение одного SQL-файла
::  Использование: call :APPLY база "путь к файлу"
:: ============================================================
:APPLY
if not exist %2 (
    echo  [ВНИМАНИЕ] SQL-файл не найден, пропуск: %2
    exit /b 0
)
echo      - применение %~nx2 к базе %1
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M %1 < %2 >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo      [ВНИМАНИЕ] Ошибка при применении %~nx2
    echo  [%date% %time%] ОШИБКА %~nx2 >> "%LOG_FILE%"
) else (
    echo  [%date% %time%] OK %~nx2 >> "%LOG_FILE%"
)
exit /b 0

:: ============================================================
::  Импорт базовой схемы только в пустую базу.
::  Раньше setup.bat при каждом запуске пересоздавал таблицы auth/characters
::  и стирал учётные записи и персонажей.
:: ============================================================
:IMPORT_IF_EMPTY
if not exist %2 (
    echo  [ОШИБКА] Не найдена схема %2
    exit /b 1
)
set "LF_TABLES="
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='%~1'" > "%TMP_DIR%\lf_count.txt" 2>>"%LOG_FILE%"
set /p LF_TABLES=<"%TMP_DIR%\lf_count.txt"
del /q "%TMP_DIR%\lf_count.txt" >nul 2>&1
if not defined LF_TABLES set "LF_TABLES=0"
if not "%LF_TABLES%"=="0" (
    echo      - база %~1 уже содержит таблиц: %LF_TABLES% - пропуск, данные сохранены
    exit /b 0
)
echo      - импорт схемы %~nx2 в пустую базу %~1
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" %~1 < %2 >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось импортировать схему %~1. Подробности: %LOG_FILE%
    exit /b 1
)
exit /b 0

:SETUP_FAIL
echo.
echo  [ВНИМАНИЕ] Установка прервана. Исправьте ошибку и запустите setup.bat снова.
echo      Журнал: %LOG_FILE%
echo.
pause
exit /b 1
