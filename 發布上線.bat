@echo off
setlocal
cd /d "%~dp0"

echo.
echo ========================================
echo   旅遊記帳 - 發布上線
echo ========================================
echo.

git add -A
if errorlevel 1 goto fail

git diff --cached --quiet
if not errorlevel 1 (
    echo 沒有新的檔案變更，檢查是否有尚未上傳的內容...
    goto dopush
)

echo 這次的變更：
git diff --cached --stat
echo.

set "MSG="
set /p MSG=請輸入這次改了什麼（直接按 Enter 用預設）: 
if not defined MSG set "MSG=更新"

git commit -m "%MSG%"
if errorlevel 1 goto fail

:dopush
git rev-list --count origin/main..HEAD > "%TEMP%\_ahead.txt" 2>nul
set /p AHEAD=<"%TEMP%\_ahead.txt"
del "%TEMP%\_ahead.txt" 2>nul
if "%AHEAD%"=="0" (
    echo.
    echo 目前沒有任何需要上傳的內容，網站已是最新。
    echo.
    pause
    exit /b 0
)

echo.
echo 有 %AHEAD% 個變更待上傳，開始上傳...
echo （第一次可能會跳出瀏覽器要你登入 GitHub）
echo.
git push
if errorlevel 1 goto fail

echo.
echo ========================================
echo   完成！約 30 秒後網站會更新
echo ========================================
echo.
echo https://pzm50160.github.io/japan-travel-tracker/
echo.
echo 手機上請重新整理才會看到新版。
echo.
pause
exit /b 0

:fail
echo.
echo *** 發布失敗，請看上面的錯誤訊息 ***
echo.
pause
exit /b 1
