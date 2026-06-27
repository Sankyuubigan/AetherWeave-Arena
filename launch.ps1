$projectDir = "D:\Projects\3d_game"
$godotExe = "D:\Programs\Godot\Godot_v4.7-stable\Godot_v4.7-stable_win64_console.exe"
$logFile = "$projectDir\@test\last_logs.txt"

New-Item -ItemType Directory -Path "$projectDir\@test" -Force | Out-Null
Clear-Content $logFile -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Launching game... Logs will appear in @test\last_logs.txt"

$proc = Start-Process -FilePath $godotExe `
    -ArgumentList "res://Scenes/MainArena.tscn" `
    -NoNewWindow `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $logFile `
    -PassThru

$proc.WaitForExit()

Write-Host "Game closed. Logs saved to @test\last_logs.txt"
