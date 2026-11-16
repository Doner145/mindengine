@echo off
rem Arrastre una carpeta (o PDFs) sobre este archivo para firmarlos.
rem Las firmas se leen de la carpeta "firmas" junto a este archivo y los
rem planos firmados se guardan en "firmados".
setlocal
set "AQUI=%~dp0"
if "%~1"=="" (
  echo Arrastre una carpeta con planos PDF sobre este archivo.
  pause
  exit /b 1
)
python "%AQUI%firmar_planos.py" %* --firmas "%AQUI%firmas" --salida "%AQUI%firmados"
echo.
pause
