#!/bin/sh
set -e

usage() {
    cat << EOF
使用法: $(basename "$0") [オプション]

rep2-allinone の Windows 版 ZIP パッケージを dockur/windows コンテナ内でインストール・起動テストします。

【事前準備】
初回のみ、以下のコマンドでベースとなる Windows 環境を構築し、
内部で OpenSSH サーバーを起動・自動起動設定し、公開鍵認証を設定しておく必要があります。
  mkdir -p /home/shiro/rep2-win-data
  docker run -d --name rep2-win-base --device=/dev/kvm --cap-add NET_ADMIN \\
    -v /home/shiro/rep2-win-data:/storage -e VERSION="server2022" \\
    -p 8006:8006 -p 2222:22 dockur/windows
  # http://localhost:8006 にアクセスしてセットアップ完了を待つ

オプション:
  --data-dir=DIR Windowsディスクデータディレクトリ (デフォルト: /home/shiro/rep2-win-data)
  --manual       テスト終了後もコンテナを削除せずに維持します
  -h, --help     このヘルプを表示して終了します

使用例:
  $(basename "$0")
  $(basename "$0") --data-dir=/path/to/win-data --manual
EOF
}

WIN_DATA_DIR="/home/shiro/rep2-win-data"
MANUAL_MODE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --data-dir=*)
            WIN_DATA_DIR="${1#*=}"
            shift
            ;;
        --manual)
            MANUAL_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "エラー: 未知のオプション '$1'"
            usage
            exit 1
            ;;
    esac
done

if [ ! -d "$WIN_DATA_DIR" ]; then
    echo "エラー: Windowsディスクデータディレクトリ '$WIN_DATA_DIR' が見つかりません。"
    echo "事前に dockur/windows でセットアップを行ってください。(-h で詳細を表示)"
    exit 1
fi

# パッケージの検索
PKG_PATH=$(ls dist/rep2-allinone-windows-*.zip 2>/dev/null | sort -V | tail -n 1)
if [ -z "$PKG_PATH" ]; then
    echo "エラー: dist/ ディレクトリに Windows版 ZIP パッケージが見つかりません。'make windows' を先に実行してください。"
    exit 1
fi

echo "使用パッケージ: $PKG_PATH"
echo "使用データディレクトリ: $WIN_DATA_DIR"

CONTAINER_NAME="rep2-win-test-$(date +%s)"
SSH_PORT="2222"
SSH_USER="docker"

echo "Windows コンテナを起動中..."
docker run -d --name "$CONTAINER_NAME" \
    --device=/dev/kvm --cap-add NET_ADMIN \
    -v "$WIN_DATA_DIR:/storage" \
    -v "$(pwd)/dist:/shared" \
    -p $SSH_PORT:22 \
    -p 10088:10088 \
    dockur/windows

echo "Windows と SSH の起動を待機中..."
while ! nc -z localhost $SSH_PORT 2>/dev/null; do
    sleep 5
done
echo "SSH ポートの応答を確認しました。サービスの安定化を待ちます..."
sleep 15

echo "SSH経由でテストを実行します..."
set +e
ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o PasswordAuthentication=no $SSH_USER@localhost powershell -Command - << 'EOF'
$ErrorActionPreference = "Stop"

Write-Host "ZIPファイルを展開中..."
if (Test-Path "C:\temp.zip") { Remove-Item "C:\temp.zip" -Force }
if (Test-Path "C:\rep2-test") { Remove-Item "C:\rep2-test" -Recurse -Force }

$zipName = (Get-ChildItem "\\host.lan\Data\rep2-allinone-windows-*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
Copy-Item -Path "\\host.lan\Data\$zipName" -Destination "C:\temp.zip"
Expand-Archive -Path "C:\temp.zip" -DestinationPath "C:\rep2-test" -Force

Write-Host "rep2-allinone.bat を起動中..."
Start-Process -FilePath "C:\rep2-test\rep2-allinone\rep2-allinone.bat" -WindowStyle Hidden

Write-Host "サービスの起動を待機中..."
$success = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:10088/" -UseBasicParsing -ErrorAction Stop
        if ($response.Content -match "rep2") {
            $success = $true
            break
        }
    } catch {
        if ($_.Exception.Response.StatusCode -eq 401) {
            $success = $true
            break
        }
    }
    Start-Sleep -Seconds 3
    Write-Host "待機中... ($($i + 1)/15)"
}

Write-Host "プロセスを終了中..."
Stop-Process -Name "php" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "php-cgi" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "caddy" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item -Path "C:\rep2-test" -Recurse -Force
Remove-Item -Path "C:\temp.zip" -Force

if ($success) {
    Write-Host "テスト成功: 正常なレスポンスを確認しました。"
    exit 0
} else {
    Write-Host "テスト失敗: 期待されるレスポンスが得られませんでした。"
    exit 1
}
EOF

TEST_RESULT=$?
set -e

if [ $TEST_RESULT -ne 0 ]; then
    echo "エラー: SSH接続またはテストの実行に失敗しました。"
    echo "事前に Windows コンテナ内で OpenSSH サーバーを起動し、公開鍵認証を設定しているか確認してください。"
    EXIT_CODE=1
else
    EXIT_CODE=0
fi

if [ "$MANUAL_MODE" = "true" ]; then
    echo "マニュアルモードのため、コンテナを維持します。"
    echo "コンテナ名: $CONTAINER_NAME"
    echo "アクセス先: http://localhost:10088/"
    echo "SSHアクセス: ssh -p $SSH_PORT $SSH_USER@localhost"
    echo "停止・削除するには以下のコマンドを実行してください:"
    echo "  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
else
    echo "クリーンアップ中..."
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null
fi

exit ${EXIT_CODE:-0}