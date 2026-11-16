@echo off
rem ---------------------------------------------------------------------------
rem Firma automatica de planos.
rem  - Doble clic: pide elegir la carpeta con los planos PDF.
rem  - Tambien puede arrastrar una carpeta o varios PDF sobre este archivo.
rem Firmas: carpeta "firmas" junto a este archivo.
rem Resultado: carpeta "firmados" (planos + informe_firmas.csv).
rem ---------------------------------------------------------------------------
setlocal
chcp 65001 >nul
set "AQUI=%~dp0"
set "PY=%AQUI%python\python.exe"
set "PYTHONIOENCODING=utf-8"
title Firmador de planos

call "%AQUI%instalar.bat" || (pause & exit /b 1)

if not exist "%AQUI%firmas\" mkdir "%AQUI%firmas"
dir /b "%AQUI%firmas\*.png" >nul 2>&1 || (
  echo No hay firmas en la carpeta:
  echo   %AQUI%firmas
  echo Copie ahi los PNG de las firmas o use preparar_firmas.bat.
  start "" "%AQUI%firmas"
  pause
  exit /b 1
)

if not "%~1"=="" goto :con_argumentos

set "CARPETA="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description='Seleccione la carpeta con los planos PDF a firmar'; if ($d.ShowDialog() -eq 'OK') { $d.SelectedPath }"`) do set "CARPETA=%%i"
if not defined CARPETA (
  echo No se selecciono ninguna carpeta.
  pause
  exit /b 1
)
"%PY%" "%AQUI%firmar_planos.py" "%CARPETA%" --firmas "%AQUI%firmas" --salida "%AQUI%firmados"
goto :fin

:con_argumentos
"%PY%" "%AQUI%firmar_planos.py" %* --firmas "%AQUI%firmas" --salida "%AQUI%firmados"

:fin
echo.
if exist "%AQUI%firmados\" start "" "%AQUI%firmados"
pause
