@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo ================================================
echo  JO POS - build APK
echo ================================================

where flutter >nul 2>nul
if errorlevel 1 (
  echo [X] Flutter is not installed or not in PATH.
  echo     Install: https://docs.flutter.dev/get-started/install/windows/mobile
  pause & exit /b 1
)

if not exist android (
  echo [1/4] Creating the Android project...
  copy /y pubspec.yaml pubspec.yaml.bak >nul
  call flutter create --platforms=android --project-name jo_pos_mobile --org com.joroyalty .
  if errorlevel 1 goto :err
  copy /y pubspec.yaml.bak pubspec.yaml >nul
  del pubspec.yaml.bak
  if exist test rmdir /s /q test
) else (
  echo [1/4] android\ already exists - skipping flutter create
)

echo [2/4] Patching permissions / name / icons...
python tools\patch_android.py 2>nul || py tools\patch_android.py
if errorlevel 1 goto :err

echo [3/4] Getting packages...
call flutter pub get
if errorlevel 1 goto :err

echo [4/4] Building release APK...
call flutter build apk --release
if errorlevel 1 goto :err

if not exist dist mkdir dist
copy /y build\app\outputs\flutter-apk\app-release.apk dist\JO_POS.apk >nul
echo.
echo  DONE:  %~dp0dist\JO_POS.apk
echo  Copy it to the phone and install (allow "unknown sources").
pause
exit /b 0

:err
echo.
echo [X] Build failed - see the messages above.
pause
exit /b 1
