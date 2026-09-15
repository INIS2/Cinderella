@echo off
setlocal DisableDelayedExpansion
set "CINDERELLA_ARGS=%*"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--dry-run=-DryRun%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--browser=-Browser%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--files=-Files%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--recycle-bin=-RecycleBin%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--all=-All%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--path=-Path%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--drive=-Drive%"
set "CINDERELLA_ARGS=%CINDERELLA_ARGS:--yes=-Yes%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Cinderella.ps1" %CINDERELLA_ARGS%
