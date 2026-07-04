@echo off
cd /d "%~dp0"
echo Pushing to GitHub...
git push origin main
git push origin main:preview
echo.
echo Done! Press any key to close.
pause >nul
