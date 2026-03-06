#!/bin/sh
set -e

usage() {
    cat << EOF
使用法: $(basename "$0") [オプション]

rep2-allinone の DEB または RPM パッケージを systemd コンテナ内でインストール・起動テストします。

オプション:
  --type=TYPE    パッケージ形式を指定 (deb または rpm, デフォルト: deb)
  --repo         ローカルのパッケージではなく、公式リポジトリからインストールします
  --manual       テスト終了後もコンテナを削除せずに維持します
  -h, --help     このヘルプを表示して終了します

使用例:
  $(basename "$0") --type=deb
  $(basename "$0") --type=rpm --repo
EOF
}

TYPE="deb"
REPO_MODE=false
MANUAL_MODE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --type=*)
            TYPE="${1#*=}"
            shift
            ;;
        --repo)
            REPO_MODE=true
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

if [ "$TYPE" = "deb" ]; then
    PKG_EXT="deb"
    IMAGE_NAME="jrei/systemd-debian:trixie"
    # systemd-debian image already has systemd/dbus.
    if [ "$REPO_MODE" = "true" ]; then
        INSTALL_CMD="apt-get update && apt-get install -y openssl curl ca-certificates gnupg && \
            curl -fsSL https://fukumen.github.io/rep2-allinone/apt/fukumen.gpg.key | gpg --dearmor -o /usr/share/keyrings/rep2-allinone-keyring.gpg && \
            echo \"deb [signed-by=/usr/share/keyrings/rep2-allinone-keyring.gpg] https://fukumen.github.io/rep2-allinone/apt ./\" | tee /etc/apt/sources.list.d/rep2-allinone.list && \
            apt-get update && apt-get install -y rep2-allinone"
    else
        INSTALL_CMD="apt-get update && apt-get install -y openssl curl ca-certificates && dpkg -i /root/package.deb || apt-get install -f -y"
    fi
elif [ "$TYPE" = "rpm" ]; then
    PKG_EXT="rpm"
    IMAGE_NAME="almalinux/10-init"
    # Pre-install dependencies to ensure they are available for RPM post-install scripts.
    # Then install the package itself.
    if [ "$REPO_MODE" = "true" ]; then
        INSTALL_CMD="dnf install -y --allowerasing openssl curl ca-certificates && \
            cat <<EOF | tee /etc/yum.repos.d/rep2-allinone.repo
[rep2-allinone]
name=rep2-allinone Repository
baseurl=https://fukumen.github.io/rep2-allinone/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://fukumen.github.io/rep2-allinone/rpm/fukumen.gpg.key
EOF
            dnf install -y rep2-allinone"
    else
        INSTALL_CMD="dnf install -y --allowerasing openssl curl ca-certificates && dnf install -y /root/package.rpm"
    fi
else
    echo "エラー: サポートされていないパッケージ形式です: $TYPE (deb または rpm を指定してください)"
    usage
    exit 1
fi

if [ "$REPO_MODE" = "false" ]; then
    PKG_PATH=$(ls dist/*.$PKG_EXT 2>/dev/null | sort -V | tail -n 1)
    if [ -z "$PKG_PATH" ]; then
        echo "エラー: dist/ ディレクトリに .$PKG_EXT パッケージが見つかりません。'make $TYPE' を先に実行してください。"
        exit 1
    fi
fi

echo "テスト形式: $TYPE (Repo: $REPO_MODE)"
[ "$REPO_MODE" = "false" ] && echo "使用パッケージ: $PKG_PATH"
echo "使用イメージ: $IMAGE_NAME"

CONTAINER_NAME="rep2-systemd-test-$(date +%s)"

echo "systemd コンテナを起動中..."
docker run -d --name "$CONTAINER_NAME" \
    --privileged \
    --cgroupns=host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    -p 10088:10088 \
    "$IMAGE_NAME"

# Wait for systemd to initialize
sleep 10

if [ "$REPO_MODE" = "false" ]; then
    docker cp "$PKG_PATH" "$CONTAINER_NAME":/root/package.$PKG_EXT
fi
docker exec "$CONTAINER_NAME" sh -c "$INSTALL_CMD"

echo "サービスの起動を待機中..."
MAX_RETRIES=15
COUNT=0
SUCCESS=false
HTTP_STATUS="Unknown"

while [ $COUNT -lt $MAX_RETRIES ]; do
    STATE=$(docker exec "$CONTAINER_NAME" systemctl is-active rep2-allinone || echo "inactive")
    if [ "$STATE" = "active" ]; then
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:10088/ || echo "Failed")
        if [ "$HTTP_STATUS" = "401" ]; then
            if curl -s http://localhost:10088/ | grep -q "rep2"; then
                SUCCESS=true
                break
            fi
        fi
    fi
    echo "待機中... (Service: $STATE, Status: $HTTP_STATUS, Try: $((COUNT + 1))/$MAX_RETRIES)"
    COUNT=$((COUNT + 1))
    sleep 3
done

if [ "$SUCCESS" = "true" ]; then
    echo "成功: systemd コンテナ内で rep2-allinone サービスが正常に起動し、初期画面（401 Unauthorized）が確認できました。"
else
    echo "失敗: 接続テストがタイムアウトしたか、期待されるレスポンスが得られませんでした。"
    echo "最終 HTTP Status: $HTTP_STATUS"
    echo "--- Systemd Status ---"
    docker exec "$CONTAINER_NAME" systemctl status rep2-allinone || true
    echo "--- Container Logs (Journalctl) ---"
    docker exec "$CONTAINER_NAME" journalctl -u rep2-allinone --no-pager | tail -n 50 || true
    EXIT_CODE=1
fi

if [ "$MANUAL_MODE" = "true" ]; then
    echo "マニュアルモードのため、コンテナを維持します。"
    echo "コンテナ名: $CONTAINER_NAME"
    echo "アクセス先: http://localhost:10088/"
    echo "コンテナ内に入るには: docker exec -it $CONTAINER_NAME sh"
    echo "停止・削除するには以下のコマンドを実行してください:"
    echo "  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
else
    echo "クリーンアップ中..."
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null
    if [ "$SUCCESS" = "true" ]; then
        echo "使用したイメージを削除中: $IMAGE_NAME"
        docker rmi "$IMAGE_NAME" 2>/dev/null || true
    fi
fi

exit ${EXIT_CODE:-0}
