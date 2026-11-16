@echo off
rem ---------------------------------------------------------------------------
rem Prepara un Python portable en la subcarpeta "python" (solo la primera vez).
rem No instala nada en Windows ni requiere permisos de administrador.
rem Lo llaman firmar.bat y preparar_firmas.bat; no hace falta ejecutarlo a mano.
rem ---------------------------------------------------------------------------
setlocal
set "AQUI=%~dp0"
set "PY=%AQUI%python\python.exe"
set "PYVER=3.12.7"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -Command"

rem Si ya esta todo instalado, salir de inmediato.
if exist "%PY%" (
  "%PY%" -c "import pdfplumber, pypdf, reportlab, PIL, numpy" >nul 2>&1 && exit /b 0
)

echo.
echo Primera ejecucion: se descargara Python %PYVER% portable y las librerias
echo necesarias (unos 60 MB). Esto se hace una sola vez.
echo.

set "ARQ=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARQ=arm64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "ARQ=win32"

if not exist "%PY%" (
  echo [1/3] Descargando Python %PYVER% [%ARQ%]...
  %PS% "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; $z=Join-Path $env:TEMP 'python-embed-firmador.zip'; Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/%PYVER%/python-%PYVER%-embed-%ARQ%.zip' -OutFile $z; Expand-Archive -Force -Path $z -DestinationPath '%AQUI%python'; Remove-Item $z" || goto :error
  rem Habilitar site-packages en el Python portable.
  %PS% "$ErrorActionPreference='Stop'; $f=Get-ChildItem '%AQUI%python\python*._pth' | Select-Object -First 1; (Get-Content $f.FullName) -replace '^#\s*import site','import site' | Set-Content $f.FullName" || goto :error
)

if not exist "%AQUI%python\Scripts\pip.exe" (
  echo [2/3] Instalando pip...
  %PS% "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -UseBasicParsing -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%AQUI%python\get-pip.py'" || goto :error
  "%PY%" "%AQUI%python\get-pip.py" --no-warn-script-location -q || goto :error
)

echo [3/3] Instalando librerias...
"%PY%" -m pip install --no-warn-script-location --disable-pip-version-check -q -r "%AQUI%requirements.txt" || goto :error
"%PY%" -c "import pdfplumber, pypdf, reportlab, PIL, numpy" || goto :error
echo Instalacion lista.
echo.
exit /b 0

:error
echo.
echo ERROR: no se pudo preparar Python.
echo  - Revise la conexion a internet.
echo  - Si la empresa usa proxy o bloquea descargas, pida a TI acceso a
echo    www.python.org, bootstrap.pypa.io, pypi.org y files.pythonhosted.org
echo  - Para reintentar desde cero, borre la carpeta "python" y vuelva a ejecutar.
exit /b 1
