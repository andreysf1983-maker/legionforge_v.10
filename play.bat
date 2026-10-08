@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::   LEGIONFORGE 7.3.5 — Запуск сервера и клиента
::   Файл: play.bat
::
::   Что делает:
::     1. Проверяет наличие MySQL и запускает его при необходимости
::     2. Применяет недостающие SQL-патчи (идемпотентные)
::     3. Запускает bnetserver (порт 1119) и ждёт его готовности
::     4. Запускает worldserver (порт 8085) и ждёт его готовности
::     5. Запускает клиент игры с патчем подключения
::
::   Повторный запуск безопасен: работающие процессы не дублируются.
::   Кодировка: UTF-8 без BOM, кодовая страница 65001.
:: ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SERVER_DIR=%ROOT%\server"
set "SQL_DIR=%ROOT%\sql"
set "TMP_DIR=%ROOT%\setup_tmp"
set "MYSQL_CNF=%TMP_DIR%\mysql.cnf"
set "LOG_FILE=%ROOT%\play_log.txt"

title LEGIONFORGE 7.3.5 - Запуск сервера
color 0A

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5 — запуск сервера
echo  =========================================================
echo.
echo  [%date% %time%] Запуск > "%LOG_FILE%"

:: ---- Проверка установленного сервера ----
if not exist "%SERVER_DIR%\worldserver.exe" (
    echo  [ВНИМАНИЕ] worldserver.exe не найден в папке server
    echo      Сначала выполните установку: setup.bat
    pause
    exit /b 1
)
if not exist "%SERVER_DIR%\bnetserver.exe" (
    echo  [ВНИМАНИЕ] bnetserver.exe не найден в папке server
    echo      Сначала выполните установку: setup.bat
    pause
    exit /b 1
)

:: ---- Поиск MySQL ----
echo  [*] Проверка MySQL...
set "MYSQL="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_mysql.ps1" -Port 3306`) do set "MYSQL=%%P"
if not exist "%MYSQL%" (
    echo  [ВНИМАНИЕ] MySQL не найден или не запущен.
    echo      Запустите setup.bat для установки и настройки MySQL.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_mysql.ps1" -Port 3306 -EnsureRunning >nul 2>&1
echo  [OK] MySQL доступен: %MYSQL%

:: ---- Применение недостающих SQL-патчей ----
echo.
echo  [*] Проверка и применение SQL-патчей LEGIONFORGE...
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\apply_play_sql.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%" >nul 2>&1
echo  [OK] SQL-патчи проверены.

:: ---- Пути MySQL/исходников в конфигах (без них worldserver закрывается сразу после старта) ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\patch_conf_paths.ps1" -Root "%ROOT%" -MysqlExe "%MYSQL%"

:: ---- Проверка портов и запуск bnetserver ----
echo.
call :CHECKPORT 1119
if "!PORT_BUSY!"=="1" (
    echo  [OK] bnetserver уже работает, порт 1119 занят.
) else (
    echo  [*] Запуск bnetserver...
    start "LEGIONFORGE bnetserver" /min cmd /c "cd /d "%SERVER_DIR%" && bnetserver.exe -c bnetserver.conf || pause"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\wait_bnet_ready.ps1" -ServerDir "%SERVER_DIR%" -Port 1119 -MaxWaitSec 45
    if errorlevel 1 (
        echo  [ВНИМАНИЕ] bnetserver не запустился за 45 секунд.
        echo      Проверьте файл %SERVER_DIR%\bnetserver.log
        pause
        exit /b 1
    )
    echo  [OK] bnetserver запущен и слушает порт 1119.
)

:: ---- Запуск worldserver ----
call :CHECKPORT 8085
if "!PORT_BUSY!"=="1" (
    echo  [OK] worldserver уже работает, порт 8085 занят.
) else (
    echo  [*] Запуск worldserver, загрузка мира занимает 1-3 минуты...
    start "LEGIONFORGE worldserver" /min cmd /c "cd /d "%SERVER_DIR%" && worldserver.exe -c worldserver.conf || pause"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\wait_world_ready.ps1" -ServerDir "%SERVER_DIR%" -Port 8085
    if errorlevel 1 (
        echo  [ВНИМАНИЕ] worldserver не подтвердил готовность.
        echo      Проверьте журнал: %SERVER_DIR%\Server.log
        pause
        exit /b 1
    )
    echo  [OK] worldserver запущен и готов принимать игроков.
)

:: ---- Состояние сервера ----
echo.
echo  [*] Состояние сервера:
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\server_status.ps1" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"

:: ---- Запуск клиента ----
echo.
set "CLIENT_EXE="
if exist "%ROOT%\client_path.txt" (
    set /p CLIENT_EXE=<"%ROOT%\client_path.txt"
)
if not exist "!CLIENT_EXE!" (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_client.ps1" -Root "%ROOT%" -SavedPathFile "%ROOT%\client_path.txt"`) do set "CLIENT_EXE=%%P"
)

if exist "!CLIENT_EXE!" (
    for %%I in ("!CLIENT_EXE!") do set "CLIENT_DIR=%%~dpI"
    echo  [*] Применение патча клиента...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\patch_client.ps1" -ClientDir "!CLIENT_DIR!" >nul 2>&1
    echo  [*] Запуск клиента: !CLIENT_EXE!
    start "" /D "!CLIENT_DIR!" "!CLIENT_EXE!"
) else (
    echo  [ВНИМАНИЕ] Клиент игры не найден.
    echo      Запустите Wow-64.exe вручную из папки клиента.
)

echo.
echo  =========================================================
echo   Сервер LEGIONFORGE запущен.
echo  =========================================================
echo.
echo   Вход в игру:
echo     Логин:   admin@legionforge.ru
echo     Пароль:  legionforge
echo.
echo   Остановка сервера: закройте окна bnetserver и worldserver
echo   или используйте файл stop_server.bat.
echo.
echo   Основные консольные команды worldserver:
echo     .server info   - информация о сервере
echo     .gm on         - включить режим мастера игры
echo     .tele          - телепортация по имени точки
echo     .npc           - работа с неигровыми персонажами
echo.
pause
exit /b 0

:: ============================================================
::  Подпрограмма применения SQL-файла: call :APPLY база "файл"
:: ============================================================
:APPLY
if not exist %2 exit /b 0
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M %1 < %2 >nul 2>&1
echo  [%date% %time%] %~nx2 к базе %1, код ошибки !errorlevel! >> "%LOG_FILE%"
exit /b 0

:: ============================================================
::  Подпрограмма проверки порта: call :CHECKPORT порт
::  Результат в переменной PORT_BUSY: 1 - занят, 0 - свободен
:: ============================================================
:CHECKPORT
set "PORT_BUSY=0"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr "LISTENING" ^| findstr ":%1 "') do set "PORT_BUSY=1"
exit /b 0
