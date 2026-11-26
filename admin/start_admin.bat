@echo off
rem Unified dev admin (Q51): ONE bat -> ONE port 8181 -> hub page with skills
rem admin + catalogs (3D objects / enemies / animations / A-B audio).
rem Catalogs are served statically from tools\ (docroot = project root),
rem viewer pages need NO edits. Dump is regenerated BEFORE server start,
rem so skills data is always fresh.
rem
rem IMPORTANT: keep this file PURE ASCII (no Cyrillic, no chcp)! cmd.exe
rem re-parses the batch after a codepage switch; chcp 65001 + multibyte
rem Cyrillic breaks parsing with "... was unexpected at this time." and the
rem bat dies before anything starts (bug 22.11.22, verified + web-confirmed).
cd /d "%~dp0\.."
netstat -ano | findstr ":8181 " | findstr "LISTENING" >nul && (
  echo Port 8181 is busy: admin is probably already running, or another process holds the port.
  start "" "http://localhost:8181/"
  pause
  exit /b 1
)
echo [1/3] Regenerating skills dump (temp/skills_dump.json)...
"D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/export_skills_json.gd
echo [2/3] Regenerating animation library dump (temp/anim_library.json)...
"D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/export_anim_library.gd
echo [3/3] Starting server on http://localhost:8181/ ...
start "" "http://localhost:8181/"
python "%~dp0server.py"
