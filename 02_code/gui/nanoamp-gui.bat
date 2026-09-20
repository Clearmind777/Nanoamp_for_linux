@echo off
REM Windows launcher for the nanoamp Shiny GUI.
Rscript --vanilla "%~dp0run_gui.R"
if errorlevel 1 pause
