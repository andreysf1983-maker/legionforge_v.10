@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
::   LEGIONFORGE 7.3.5 — Извлечение игровых данных
::   Файл: extract_maps.bat
::
::   Извлекает из клиента WoW 7.3.5 файлы:
::     maps   - геометрия карт (обязательно)
::     vmaps  - видимые объекты и высоты (обязательно)
::     mmaps  - навигационные мешки для передвижения NPC (рекомендуется)
::
::   Результат помещается в папку server\data.
:: ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SERVER_DIR=%ROOT%\server"
set "TMP_DIR=%ROOT%\setup_tmp"

title LEGIONFORGE 7.3.5 - Извлечение игровых данных
color 0B

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5 — извлечение игровых данных
echo  =========================================================
echo.

if not exist "%SERVER_DIR%\mapextractor.exe" (
    echo  [ВНИМАНИЕ] Не найдены инструменты извлечения в папке server
    echo      mapextractor.exe, vmapextractor.exe, mmaps_generator.exe
    echo      Выполните установку заново: setup.bat
    pause
    exit /b 1
)

set "CLIENT_EXE="
if exist "%ROOT%\client_path.txt" set /p CLIENT_EXE=<"%ROOT%\client_path.txt"
if not exist "!CLIENT_EXE!" (
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\find_client.ps1" -Root "%ROOT%" -SavedPathFile "%ROOT%\client_path.txt"`) do set "CLIENT_EXE=%%P"
)
if not exist "!CLIENT_EXE!" (
    echo  [ВНИМАНИЕ] Клиент игры 7.3.5 не найден.
    echo      Укажите путь к клиенту вручную.
    set /p "CLIENT_INPUT=  Путь: "
    if defined CLIENT_INPUT set "CLIENT_EXE=!CLIENT_INPUT!"
)
if not exist "!CLIENT_EXE!" (
    echo  [ВНИМАНИЕ] Клиент не найден, извлечение невозможно.
    pause
    exit /b 1
)

for %%I in ("!CLIENT_EXE!") do set "CLIENT_DIR=%%~dpI"
set "CLIENT_DIR=!CLIENT_DIR:~0,-1!"
echo  [*] Клиент: !CLIENT_DIR!

echo.
echo  Режим генерации mmaps:
echo    1 - только основные континенты (быстро, рекомендуется)
echo    2 - все карты (очень долго, несколько часов)
echo    3 - пропустить генерацию mmaps
set /p "MMAP_CHOICE=  Выбор [1]: "
if "!MMAP_CHOICE!"=="" set "MMAP_CHOICE=1"

set "MMAP_MODE=priority"
if "!MMAP_CHOICE!"=="2" set "MMAP_MODE=all"
if "!MMAP_CHOICE!"=="3" set "MMAP_MODE=none"

echo.
echo  [*] Извлечение данных, не закрывайте окно...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\extract_maps.ps1" -ClientDir "!CLIENT_DIR!" -ServerDir "%SERVER_DIR%" -MmapsMode %MMAP_MODE%
if errorlevel 1 (
    echo.
    echo  [ВНИМАНИЕ] Извлечение завершилось с ошибкой.
    echo      Проверьте, что клиент 7.3.5 полный и не повреждён.
    pause
    exit /b 1
)

echo.
echo  =========================================================
echo   Игровые данные извлечены в %SERVER_DIR%\data
echo  =========================================================
echo.
pause
exit /b 0
