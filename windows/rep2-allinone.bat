@echo off
setlocal EnableDelayedExpansion

:: 展開先ディレクトリの取得
set "HERE=%~dp0"
cd /d "%HERE%"

set "DATA_BASE_DIR=%HERE%var"
set "CONF_DIR=%HERE%conf"

:: Caddyのデータ保存先
set "XDG_CONFIG_HOME=%DATA_BASE_DIR%\caddy_config"
set "XDG_DATA_HOME=%DATA_BASE_DIR%\caddy_data"
if not exist "%XDG_CONFIG_HOME%" mkdir "%XDG_CONFIG_HOME%"
if not exist "%XDG_DATA_HOME%" mkdir "%XDG_DATA_HOME%"
if not exist "%DATA_BASE_DIR%\conf" mkdir "%DATA_BASE_DIR%\conf"
if not exist "%DATA_BASE_DIR%\data" mkdir "%DATA_BASE_DIR%\data"

:: デフォルト設定ファイル・データのコピー
if not exist "%DATA_BASE_DIR%\conf\conf.inc.php" (
    xcopy "%HERE%p2-php\conf.orig\*" "%DATA_BASE_DIR%\conf\" /E /I /Y >nul 2>&1
)
if not exist "%DATA_BASE_DIR%\data\db" (
    xcopy "%HERE%p2-php\data.orig\*" "%DATA_BASE_DIR%\data\" /E /I /Y >nul 2>&1
)

:: 初期セットアップ
"%HERE%bin\php.exe" -c "%CONF_DIR%\php.ini" "%HERE%p2-php\scripts\ic2.php" setup

echo Starting PHP FastCGI server...
start "rep2-php-server" /B "%HERE%bin\php-cgi.exe" -b 127.0.0.1:9000 -c "%CONF_DIR%\php.ini"

echo Starting Caddy server...
"%HERE%bin\caddy.exe" run --config "%CONF_DIR%\Caddyfile" --adapter caddyfile

echo Stopping PHP server...
taskkill /F /FI "WINDOWTITLE eq rep2-php-server" /T >nul 2>&1
