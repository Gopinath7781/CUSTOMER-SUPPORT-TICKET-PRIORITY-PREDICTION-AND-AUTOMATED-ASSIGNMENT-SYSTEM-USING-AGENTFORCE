@echo off
REM Usage:  deploy.bat [org-alias] [--seed]
REM Run from the folder that contains sfdx-project.json
set ORG=%1
if "%ORG%"=="" set ORG=myorg

echo === 1/4 Deploying metadata to %ORG% ===
call sf project deploy start --source-dir force-app --wait 30 --target-org %ORG%
if errorlevel 1 goto fail

echo === 2/4 Assigning permission set ===
call sf org assign permset --name Support_Ticket_Intelligence_Access --target-org %ORG%

if /i not "%2"=="--seed" goto done

echo === 3/4 Inserting sample data ===
call sf apex run --file scripts\seed.apex --target-org %ORG% > nul
if errorlevel 1 goto fail

echo === 4/4 Testing the flow ===
call sf apex run --file scripts\test_flow.apex --target-org %ORG% | findstr RESULT

:done
echo.
echo Done. Now do the manual Agentforce steps in README.md
exit /b 0

:fail
echo.
echo Something failed - read the error above.
exit /b 1
