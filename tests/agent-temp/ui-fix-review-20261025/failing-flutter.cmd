@echo off
rem Temporary scope test: report the pinned SDK version, fail the build.
if "%1"=="--version" (
  echo {"frameworkVersion":"3.47.6","dartSdkVersion":"3.13.5"}
  exit /b 0
)
exit /b 23
