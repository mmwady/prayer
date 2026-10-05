@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title Prayer Action Recognizer

set "VENV_DIR=%~dp0.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

if exist "%VENV_PY%" goto :install

echo [1/3] Creating the local Python environment...
set "PYTHON_CMD="
where py >nul 2>nul && set "PYTHON_CMD=py -3"
if defined PYTHON_CMD (
  !PYTHON_CMD! --version >nul 2>nul
  if errorlevel 1 set "PYTHON_CMD="
)
if not defined PYTHON_CMD (
  where python >nul 2>nul && set "PYTHON_CMD=python"
  if defined PYTHON_CMD (
    !PYTHON_CMD! --version >nul 2>nul
    if errorlevel 1 set "PYTHON_CMD="
  )
)
if not defined PYTHON_CMD if exist "%LocalAppData%\Programs\Python\Python312\python.exe" set "PYTHON_CMD=%LocalAppData%\Programs\Python\Python312\python.exe"
if not defined PYTHON_CMD if exist "%UserProfile%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" set "PYTHON_CMD=%UserProfile%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if not defined PYTHON_CMD goto :no_python
%PYTHON_CMD% -m venv "%VENV_DIR%"
if errorlevel 1 goto :failed

:install
echo [2/3] Checking required packages...
"%VENV_PY%" -m pip install --disable-pip-version-check -q -r requirements.txt
if errorlevel 1 goto :failed

echo [3/3] Starting the app in your browser...
start "" /b powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 3; Start-Process 'http://localhost:8501'"
"%VENV_PY%" -m streamlit run app.py --server.headless true --browser.gatherUsageStats false
goto :end

:no_python
echo.
echo Python 3.10 or newer was not found.
echo Install Python from https://www.python.org/downloads/windows/
echo During setup, select "Add Python to PATH", then run this file again.
pause
goto :end

:failed
echo.
echo Setup failed. Review the error above, then run start_app.bat again.
pause

:end
endlocal
