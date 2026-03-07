$ErrorActionPreference = "Stop"
$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $HERE

$DATA_BASE_DIR = "$HERE\var"
$PHP_BIN = "$HERE\bin\php.exe"
$PHP_CGI_BIN = "$HERE\bin\php-cgi.exe"
$PHP_INI = "$HERE\conf\php.ini"
$SECRETS_FILE = "$HERE\conf\secrets.conf"
$CACERT_PEM = "$HERE\conf\cacert.pem"

# Prepare caddy data directories
$XDG_CONFIG_HOME = "$DATA_BASE_DIR\caddy_config"
$XDG_DATA_HOME = "$DATA_BASE_DIR\caddy_data"
if (!(Test-Path $XDG_CONFIG_HOME)) { New-Item -ItemType Directory -Force -Path $XDG_CONFIG_HOME | Out-Null }
if (!(Test-Path $XDG_DATA_HOME)) { New-Item -ItemType Directory -Force -Path $XDG_DATA_HOME | Out-Null }

# Initial setup: Copy default config/data to p2-php/
$confPath = "$HERE\p2-php\conf\conf.inc.php"
if (!(Test-Path $confPath)) {
    New-Item -ItemType Directory -Force -Path "$HERE\p2-php\conf" | Out-Null
    Copy-Item -Path "$HERE\p2-php\conf.orig\*" -Destination "$HERE\p2-php\conf\" -Recurse -Force
}
$dataPath = "$HERE\p2-php\data\db"
if (!(Test-Path $dataPath)) {
    New-Item -ItemType Directory -Force -Path "$HERE\p2-php\data" | Out-Null
    Copy-Item -Path "$HERE\p2-php\data.orig\*" -Destination "$HERE\p2-php\data\" -Recurse -Force
}

# Generate SECRET_KEY if not exists
if (!(Test-Path $SECRETS_FILE)) {
    Write-Host "Generating new SECRET_KEY..."
    $key = & $PHP_BIN -r "echo bin2hex(random_bytes(32));"
    "SECRET_KEY=$key" | Out-File -FilePath $SECRETS_FILE -Encoding ASCII
}

# Load SECRET_KEY and build information (Set environment variables for the process)
foreach ($file in @("$SECRETS_FILE", "$HERE\conf\build_info")) {
    if (Test-Path $file) {
        foreach ($line in Get-Content $file) {
            if ($line -match '^([^#=]+)=(.*)$') {
                [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), "Process")
            }
        }
    }
}

# Run setup
& $PHP_BIN -d extension_dir="$HERE\bin\ext" -d curl.cainfo="$CACERT_PEM" -d openssl.cafile="$CACERT_PEM" -c "$PHP_INI" "$HERE\p2-php\scripts\ic2.php" setup

# Cleanup existing processes to prevent port conflicts
Stop-Process -Name "php-cgi", "caddy" -Force -ErrorAction SilentlyContinue

try {
    Write-Host "Starting PHP FastCGI server..."
    $env:PHP_FCGI_MAX_REQUESTS = "1000"
    $phpArgs = @("-b", "127.0.0.1:9000", "-d", "extension_dir=""$HERE\bin\ext""", "-d", "curl.cainfo=""$CACERT_PEM""", "-d", "openssl.cafile=""$CACERT_PEM""", "-c", """$PHP_INI""")
    $php = Start-Process -FilePath $PHP_CGI_BIN -ArgumentList $phpArgs -NoNewWindow -PassThru

    Write-Host "Starting Caddy server..."
    & "$HERE\bin\caddy.exe" run --config "$HERE\conf\Caddyfile" --adapter caddyfile
} finally {
    Write-Host "Stopping servers..."
    Stop-Process -Name "php-cgi" -Force -ErrorAction SilentlyContinue
}
