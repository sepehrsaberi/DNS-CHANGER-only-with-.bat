@echo off
setlocal EnableDelayedExpansion

:: --- تنظیمات ---
set "CURRENT_VERSION=0.1"
set "VERSION_URL=https://raw.githubusercontent.com/USERNAME/REPO/main/version.txt"
set "SCRIPT_URL=https://raw.githubusercontent.com/USERNAME/REPO/main/dns_changer.bat"
set "TEMP_DIR=%temp%\dns_changer_update"
:: ----------------

echo Checking for updates...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:: بررسی اتصال و دانلود نسخه جدید با timeout (45 ثانیه)
powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('%VERSION_URL%', '%TEMP_DIR%\online_version.txt')" >nul 2>&1

if exist "%TEMP_DIR%\online_version.txt" (
    set /p ONLINE_VERSION=<"%TEMP_DIR%\online_version.txt"
    
    if "!CURRENT_VERSION!"=="!ONLINE_VERSION!" (
        echo You are up to date.
        timeout /t 2 >nul
    ) else (
        echo New version detected: !ONLINE_VERSION!
        echo Downloading update...
        powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('%SCRIPT_URL%', '%~dp0dns_changer_new.bat')"
        
        echo.
        echo Update completed!
        echo Please restart the script.
        pause
        exit
    )
) else (
    echo Could not check for updates. Running current version...
    timeout /t 2 >nul
)

cd /d "%~dp0"

:: دریافت دقیق‌تر DNS فعلی
echo Detecting current DNS settings...
set "CurrentDNS_Primary="
set "CurrentDNS_Secondary="

:: بررسی کارت های شبکه فعال
for /f "tokens=*" %%a in ('wmic nic where "netenabled=true" get netconnectionid ^| findstr /v "netconnectionid"') do (
    set "NIC_NAME=%%a"
    if defined NIC_NAME (
        :: گرفتن تنظیمات IP کارت شبکه
        for /f "tokens=*" %%b in ('netsh interface ip show config name^="!NIC_NAME!" ^| findstr /i "DNS Servers"') do (
            set "DNS_LINE=%%b"
            :: استخراج DNS سرورها
            set "DNS_LINE=!DNS_LINE: =!" :: حذف فاصله ها برای پردازش اسانتر
            if "!DNS_LINE!" NEQ "" (
                for /f "tokens=1,2 delims=," %%c in ("!DNS_LINE:DNS Servers: =!") do (
                    if not defined CurrentDNS_Primary set "CurrentDNS_Primary=%%c"
                    if "%%d" NEQ "" (
                         set "CurrentDNS_Secondary=%%d"
                    )
                )
            )
        )
    )
)

:: ساخت خروجی نهایی برای نمایش
set "DisplayDNS="
if defined CurrentDNS_Primary set "DisplayDNS=!CurrentDNS_Primary!"
if defined CurrentDNS_Secondary (
    if defined DisplayDNS set "DisplayDNS=!DisplayDNS! / !CurrentDNS_Secondary!"
)

if "!DisplayDNS!"=="" set "DisplayDNS=Not Found or DHCP"

:: [بخش دسترسی ادمین همانند قبل]
net session >nul 2>&1
if %errorlevel% neq 0 (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

:: نمایش DNS فعلی بالای منو
cls
echo ==================================
echo      DNS CHANGER - Pro Edition
if "!DisplayDNS!" NEQ "Not Found or DHCP" (
    echo Current DNS: !DisplayDNS!
) else (
    echo Current DNS: DHCP or Not Configured
)
echo ==================================
echo 1 - Auto Select Best DNS (Ping)
echo 2 - Manual Selection (From List)
echo 3 - Add New DNS
echo 4 - Reset to DHCP
echo 0 - Exit
echo ==================================
set "DNSFILE=dns.txt"
set /p CHOICE=Select: 
if "%CHOICE%"=="1" goto AUTODNS
if "%CHOICE%"=="2" goto SHOW_AND_SELECT
if "%CHOICE%"=="3" goto ADDDNS
if "%CHOICE%"=="4" goto RESETDNS
goto MENU
:SHOW_AND_SELECT
cls
echo Fetching Ping results, please wait...
echo ----------------------------------
set "count=0"

:: حلقه برای نمایش لیست به همراه پینگ
for /f "tokens=1,2 delims=[] " %%a in (%DNSFILE%) do (
    set /a count+=1
    set "dnsP=%%a"
    set "dnsS=%%b"
    
    :: تست پینگ (فقط یک پکت برای سرعت بالاتر)
    for /f "tokens=4 delims==" %%i in ('ping -n 1 %%a ^| find "Average"') do set "pingP=%%i"
    
    :: ذخیره در متغیرهای آرایه‌ای برای انتخاب نهایی
    set "DNS_!count!=%%a %%b"
    
    echo !count! - [%%a / %%b]  --^> Ping: !pingP!
)
echo ----------------------------------
set /p NUM="Enter number to select (or 0 to back): "

if "%NUM%"=="0" goto MENU
if defined DNS_%NUM% (
    for /f "tokens=1,2" %%A in ("!DNS_%NUM%!") do (
        echo Setting DNS...
        call :SET_DNS %%A %%B
    )
    pause
) else (
    echo Invalid Selection!
    pause
)
goto MENU

:SET_DNS
:: تغییر دی‌ان‌اس (همان منطق قبلی)
for /f "tokens=1,2" %%A in ('wmic nic where "netenabled=true" get netconnectionid ^| findstr /v "netconnectionid"') do (
    netsh interface ip set dns name="%%A" static %1 primary >nul
    netsh interface ip add dns name="%%A" %2 index=2 >nul
)
echo DNS set to: %1 and %2
goto :eof


:AUTODNS
echo Testing DNS servers, please wait...
set "BEST_AVG=9999"
set "BEST_P="
set "BEST_S="

for /f "tokens=1,2 delims=[] " %%a in (%DNSFILE%) do (
    set "p=%%a"
    set "s=%%b"
    
    :: محاسبه پینگ
    for /f "tokens=4 delims==" %%i in ('ping -n 2 !p! ^| find "Average"') do set "pingP=%%i"
    for /f "tokens=4 delims==" %%j in ('ping -n 2 !s! ^| find "Average"') do set "pingS=%%j"
    
    set /a "avg=(!pingP:~0,-2! + !pingS:~0,-2!) / 2"
    echo DNS [!p! !s!] Average Ping: !avg!ms
    
    if !avg! lss !BEST_AVG! (
        set "BEST_AVG=!avg!"
        set "BEST_P=!p!"
        set "BEST_S=!s!"
    )
)

if defined BEST_P (
    echo.
    echo Best DNS found: !BEST_P! / !BEST_S! with !BEST_AVG!ms
    call :SET_DNS !BEST_P! !BEST_S!
) else (
    echo No valid DNS found or network error.
)
pause
goto MENU

:SET_DNS
for /f "tokens=1,2" %%A in ('wmic nic where "netenabled=true" get netconnectionid ^| findstr /v "netconnectionid"') do (
    netsh interface ip set dns name="%%A" static %1 primary >nul
    netsh interface ip add dns name="%%A" %2 index=2 >nul
)
echo DNS applied successfully to all active adapters.
goto :eof

:SHOWDNS
cls
echo Current DNS List in dns.txt:
type "%DNSFILE%"
echo.
pause
goto MENU

:ADDDNS
echo Enter DNS in format: 1.1.1.1 1.0.0.1
set /p INPUT=DNS: 
echo [%INPUT%]>>"%DNSFILE%"
echo Added.
pause
goto MENU

:RESETDNS
for /f "tokens=1,2" %%A in ('wmic nic where "netenabled=true" get netconnectionid ^| findstr /v "netconnectionid"') do (
    netsh interface ip set dns name="%%A" source=dhcp
)
echo DNS reset to DHCP (Default).
pause
goto MENU
