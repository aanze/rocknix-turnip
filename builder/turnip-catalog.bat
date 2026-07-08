@echo off
REM ===========================================================================
REM  1-click Turnip driver catalogue build + publish (runs the build in WSL).
REM
REM    Double-click            -> rebuild + publish every driver in
REM                               catalog-sources.txt to aanze/rocknix-turnip
REM    turnip-catalog.bat stable:26.2.0
REM                            -> add that Mesa release to the catalogue, then
REM                               rebuild + publish everything
REM    turnip-catalog.bat git:origin/main:nightly
REM                            -> add a mesa.git snapshot (bleeding-edge a830)
REM    turnip-catalog.bat stable:26.2.0 --no-publish
REM                            -> build only, don't upload (dry run)
REM
REM  Edit the catalogue list any time:  notepad \\wsl$\Ubuntu\home\marc\scripts\rocknix-aanze\catalog-sources.txt
REM ===========================================================================
setlocal
echo Building Turnip catalogue in WSL (Ubuntu)...  this reuses the warm ROCKNIX toolchain.
echo Follow the build log from another shell:  wsl tail -f /tmp/turnip-build.log
wsl.exe -e bash -lc "/home/marc/scripts/rocknix-aanze/publish-turnip-catalog.sh %*"
echo.
echo Done. Press any key to close.
pause >nul
