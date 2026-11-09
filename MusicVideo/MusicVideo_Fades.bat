@echo off
setlocal

rem Uso: arrastrar el video grabado por OBS (.mkv) sobre este .bat
rem Requiere ffmpeg y ffprobe en el PATH.

set "IN=%~1"
if "%IN%"=="" (
    echo Arrastra el video sobre este .bat
    pause
    exit /b 1
)

rem Duracion de cada fade en segundos
set FADE=1

for /f %%d in ('ffprobe -v error -show_entries format^=duration -of csv^=p^=0 "%IN%"') do set DUR=%%d

for /f %%s in ('powershell -nologo -command "[math]::Round(%DUR% - %FADE%, 3).ToString([cultureinfo]::InvariantCulture)"') do set OUTST=%%s

echo Duracion: %DUR% s  -  fade out desde: %OUTST% s

ffmpeg -i "%IN%" ^
  -vf "fade=t=in:st=0:d=%FADE%,fade=t=out:st=%OUTST%:d=%FADE%" ^
  -af "afade=t=in:st=0:d=%FADE%,afade=t=out:st=%OUTST%:d=%FADE%" ^
  -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p ^
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 ^
  -c:a aac -b:a 320k -movflags +faststart ^
  "%~dpn1_final.mp4"

pause
