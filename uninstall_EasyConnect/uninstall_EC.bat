@echo off
title EasyConnect / Sangfor Deep Cleaner

:: ============================================================================
:: 0.自动申请管理员权限
:: ============================================================================
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

echo ========================================================
echo   Starting EasyConnect / Sangfor Deep Clean...
echo ========================================================
echo.

:: ============================================================================
:: 1.强杀残余进程
:: ============================================================================
echo [1/5] Killing running Sangfor and EasyConnect processes...
taskkill /f /im EasyConnect* /t >nul 2>&1
taskkill /f /im Sangfor* /t >nul 2>&1
taskkill /f /im ECGui* /t >nul 2>&1
taskkill /f /im svpn* /t >nul 2>&1

:: ============================================================================
:: 2.移除系统服务与底层驱动注册项
:: ============================================================================
echo [2/5] Removing system services and driver registry entries...
for %%s in (SangforPromoteService SangforUD svpnservice SangforNdis SangforWfp SangforTcp) do (
    sc stop "%%s" >nul 2>&1
    sc delete "%%s" >nul 2>&1
    reg delete "HKLM\SYSTEM\CurrentControlSet\Services\%%s" /f >nul 2>&1
)

:: ============================================================================
:: 3.夺取权限并强删残留目录
:: ============================================================================
echo [3/5] Taking ownership and deleting Sangfor directories...

for %%d in (
    "C:\Program Files (x86)\Sangfor"
    "C:\Program Files\Sangfor"
    "C:\ProgramData\Sangfor"
    "%AppData%\Sangfor"
    "%LocalAppData%\Sangfor"
) do (
    if exist %%d (
        echo   - Processing %%d ...
        takeown /f %%d /r /d y >nul 2>&1
        icacls %%d /grant administrators:F /t >nul 2>&1
        rd /s /q %%d >nul 2>&1
        
        :: 如果依然被内核锁死删不掉，改名删除
        if exist %%d (
            echo   [!] Folder locked by kernel, renaming to .bak for deletion after reboot...
            ren %%d "Sangfor_trash_%random%.bak" >nul 2>&1
        )
    )
)

:: 清理 Temp 临时目录残留
del /f /s /q "%Temp%\Sangfor*" >nul 2>&1
del /f /s /q "%Temp%\EasyConnect*" >nul 2>&1

:: ============================================================================
:: 4.清除 System32 下的内核驱动文件
:: ============================================================================
echo [4/5] Cleaning kernel drivers in System32 and SysWOW64...
for %%f in (
    "C:\Windows\System32\drivers\Sangfor*.sys"
    "C:\Windows\System32\drivers\svpn*.sys"
    "C:\Windows\SysWOW64\Sangfor*"
) do (
    takeown /f "%%f" >nul 2>&1
    icacls "%%f" /grant administrators:F >nul 2>&1
    del /f /q "%%f" >nul 2>&1
)

:: ============================================================================
:: 5.清理注册表残留与浏览器唤醒协议
:: ============================================================================
echo [5/5] Cleaning Registry keys and URL protocols...
reg delete "HKCU\Software\Sangfor" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Sangfor" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Sangfor" /f >nul 2>&1
reg delete "HKCR\sangfor" /f >nul 2>&1
reg delete "HKCR\easyconnect" /f >nul 2>&1

:: 移除常见的开机自启项
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "EasyConnect" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "EasyConnect" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" /v "EasyConnect" /f >nul 2>&1

echo.
echo ========================================================
echo   All Done! 
echo   NOTE: If you used "msconfig" to enter Safe Mode, 
echo   remember to uncheck "Safe boot" before restarting!
echo ========================================================
echo.
echo 海饼干留：
echo 如果发现重启以退出安全模式后，计算机联网情况下无法打开网页
echo 请用管理员模式打开cmd后逐行输入以下命令，完成后重启计算机：
echo netsh winsock reset
echo netsh int ip reset
echo ipconfig /flushdns
echo.
pause