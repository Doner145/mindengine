@echo off
rem ---------------------------------------------------------------------------
rem Prepara las firmas: toma los escaneos/fotos de la carpeta "escaneos",
rem quita el fondo, recorta y guarda los PNG en la carpeta "firmas".
rem Nombre cada escaneo como figura en el cajetin, p. ej. "A. CALLUPE.jpg".
rem ---------------------------------------------------------------------------
setlocal
chcp 65001 >nul
set "AQUI=%~dp0"
set "PY=%AQUI%python\python.exe"
set "PYTHONIOENCODING=utf-8"
title Preparar firmas

call "%AQUI%instalar.bat" || (pause & exit /b 1)

if not exist "%AQUI%escaneos\" mkdir "%AQUI%escaneos"
dir /b "%AQUI%escaneos\*.*" >nul 2>&1 || (
  echo Copie los escaneos o fotos de las firmas en:
  echo   %AQUI%escaneos
  echo Nombre cada archivo como figura en el cajetin, p. ej. "A. CALLUPE.jpg".
  echo Luego vuelva a ejecutar este archivo.
  start "" "%AQUI%escaneos"
  pause
  exit /b 1
)

"%PY%" "%AQUI%preparar_firmas.py" "%AQUI%escaneos" "%AQUI%firmas" %*
echo.
echo Revise las firmas generadas en la carpeta "firmas".
start "" "%AQUI%firmas"
pause
