@echo off
REM ===========================================================================
REM  Interactive Turnip variant builder (KIMCHI-style) for ROCKNIX.
REM
REM  Double-click to launch a guided flow in WSL:
REM    1. pick a Mesa base (latest stable / a tag / latest mesa-git / a commit)
REM    2. optionally cherry-pick GitLab Merge Requests (by number)
REM    3. optionally apply local .patch files
REM    4. name it -> builds in the ROCKNIX toolchain -> publishes to your catalogue
REM
REM  The device then sees it under Perf Control > DRIVER > "Refresh catalog".
REM
REM  For a plain version with no patches, the simpler turnip-catalog.bat is enough
REM  (e.g.  turnip-catalog.bat stable:26.2.0 ).
REM ===========================================================================
echo Launching the interactive Turnip builder in WSL (Ubuntu)...
echo Follow the build log from another shell:  wsl tail -f /tmp/turnip-build.log
wsl.exe -e bash -lic "/home/marc/scripts/rocknix-aanze/turnip-builder.sh"
echo.
echo Finished. Press any key to close.
pause >nul
