@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
title mypac 服务管理

:: ============================================================
::  mypac Windows 服务脚本
::  默认操作：重启（先按端口关闭旧进程，再后台启动新实例）
:: ============================================================

:: ---------- 配置区 ----------
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SERVER_PY=%SCRIPT_DIR%\server.py"
set "PORT=10390"
set "HOST=0.0.0.0"

:: 从 .env 读取 PAC_PORT（如果存在）
if exist "%SCRIPT_DIR%\.env" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%SCRIPT_DIR%\.env") do (
        set "_key=%%a"
        set "_val=%%b"
        :: 去空格
        set "_key=!_key: =!"
        if /i "!_key!"=="PAC_PORT" (
            set "_val=!_val: =!"
            set "PORT=!_val!"
        )
    )
)

:: ---------- 定位 Python ----------
set "PYTHON_EXE="
for %%P in (python py python3) do (
    if not defined PYTHON_EXE (
        where %%P >nul 2>&1 && set "PYTHON_EXE=%%P"
    )
)
if not defined PYTHON_EXE (
    echo [错误] 未找到 Python，请先安装并加入 PATH。
    echo        下载: https://www.python.org/downloads/
    pause
    exit /b 1
)

:: ---------- 解析参数（默认重启） ----------
set "ACTION=restart"
if /i "%~1"=="start"   set "ACTION=start"
if /i "%~1"=="stop"    set "ACTION=stop"
if /i "%~1"=="restart" set "ACTION=restart"
if /i "%~1"=="status"  set "ACTION=status"

if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?" goto :usage

:: ---------- 分发 ----------
if /i "%ACTION%"=="status"  goto :status
if /i "%ACTION%"=="stop"    goto :stop
if /i "%ACTION%"=="start"   goto :start
if /i "%ACTION%"=="restart" goto :restart

goto :usage

:: ============================================================
::  STATUS — 查看运行状态
:: ============================================================
:status
echo.
echo === mypac 状态检查 ===
call :find_pid
if "!FOUND_PID!"=="" (
    echo   [ ] 服务未运行
) else (
    echo   [√] 服务运行中  PID=!FOUND_PID!  端口=%PORT%
)
echo.
goto :end

:: ============================================================
::  STOP — 关闭服务
:: ============================================================
:stop
echo.
echo === 停止 mypac ===
call :find_pid
if "!FOUND_PID!"=="" (
    echo   服务未运行，无需操作。
) else (
    echo   正在终止 PID=!FOUND_PID! ...
    taskkill /PID !FOUND_PID! /F >nul 2>&1
    :: 等待端口释放
    timeout /t 1 /nobreak >nul 2>&1
    call :find_pid
    if "!FOUND_PID!"=="" (
        echo   [√] 已停止
    ) else (
        echo   [!] 端口 %PORT% 仍被占用，请手动检查: netstat -ano ^| findstr :%PORT%
    )
)
echo.
goto :end

:: ============================================================
::  START — 后台启动服务
:: ============================================================
:start
echo.
echo === 启动 mypac ===
call :find_pid
if not "!FOUND_PID!"=="" (
    echo   [!] 端口 %PORT% 已被占用（PID=!FOUND_PID!）。请先 stop 或 restart。
    echo.
    goto :end
)
if not exist "%SERVER_PY%" (
    echo   [错误] 找不到 server.py: %SERVER_PY%
    goto :end
)
echo   Python  : %PYTHON_EXE%
echo   脚本    : %SERVER_PY%
echo   监听    : %HOST%:%PORT%
echo   日志    : %SCRIPT_DIR%\.cache\logs\ (按天滚动)
:: 用 pythonw 后台运行（无控制台窗口）；回退到 start /B python
set "PYTHONW=%PYTHON_EXE%"
where pythonw >nul 2>&1 && set "PYTHONW=pythonw"
start "" /B "%PYTHONW%" "%SERVER_PY%"
:: 给进程一点时间绑定端口
timeout /t 2 /nobreak >nul 2>&1
call :find_pid
if "!FOUND_PID!"=="" (
    echo   [!] 启动后未检测到监听，可能启动失败。请手动运行查看错误:
    echo       %PYTHON_EXE% "%SERVER_PY%"
    echo   或查看日志: type "%SCRIPT_DIR%\.cache\logs\mypac.log"
) else (
    echo.
    echo   [√] 启动成功  PID=!FOUND_PID!
    echo   本机 PAC : http://127.0.0.1:%PORT%
    for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /C:"IPv4"') do (
        set "LANIP=%%a"
        set "LANIP=!LANIP: =!"
    )
    if defined LANIP echo   局域网  : http://!LANIP!:%PORT%
)
echo.
goto :end

:: ============================================================
::  RESTART — 重启（默认）
:: ============================================================
:restart
echo.
echo === 重启 mypac ===
call :stop
call :start
goto :end

:: ============================================================
::  子程序：查找占用 PORT 的 PID
:: ============================================================
:find_pid
set "FOUND_PID="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr "LISTENING" ^| findstr ":%PORT% "') do (
    if not defined FOUND_PID set "FOUND_PID=%%a"
)
goto :eof

:: ============================================================
:usage
:: ============================================================
echo.
echo mypac 服务管理脚本 (Windows)
echo.
echo 用法:
echo   mypac.bat             重启服务（默认：先停后启）
echo   mypac.bat restart     重启服务
echo   mypac.bat start       后台启动服务
echo   mypac.bat stop        停止服务
echo   mypac.bat status      查看状态
echo   mypac.bat help        显示帮助
echo.
goto :end

:end
if /i "%~1"=="" timeout /t 3 /nobreak >nul 2>&1
endlocal
