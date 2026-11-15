@echo off
rem Start the Neovim selected with nvim-version.ps1 with the installed config (NVIM_APPNAME from .appname).
rem Not needed for the default install, where plain `nvim` does the same; useful for -AppName installs.
setlocal
set "HERE=%~dp0.."
set "VERS=%HERE%\versions"
if defined HEES_NVIM_VERSIONS set "VERS=%HEES_NVIM_VERSIONS%"
set "APP=nvim"
if exist "%HERE%\.appname" set /p APP=<"%HERE%\.appname"
if not exist "%VERS%\current\bin\nvim.exe" (
  echo nvk: no Neovim selected. Run: "%HERE%\nvim-version.ps1" install stable 1>&2
  exit /b 1
)
set "NVIM_APPNAME=%APP%"
"%VERS%\current\bin\nvim.exe" %*
exit /b %ERRORLEVEL%
