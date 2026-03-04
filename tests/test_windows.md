# rep2-allinone Windows 版パッケージ自動テストセットアップガイド

このドキュメントでは、Linux ホスト上で Windows 版 ZIP パッケージの動作テストを自動化するための
`tests/test_dist_pkg_win.sh` のセットアップ方法について説明します。

## 1. 仕組み

- `dockur/windows` Docker イメージを使用して、Linux 上の KVM/QEMU で Windows を実行します。
- Windows Server 2022 (180日間評価版) を使用し、ライセンス購入なしでテスト可能です。
- SSH (PowerShell) 経由でパッケージの展開・起動・HTTP テストを実行します。
- ホストの `dist` ディレクトリを Windows 内に SMB 共有 (`\\host.lan\Data`) としてマウントします。

## 2. 前提条件

- **ホストOS:** Linux (Ubuntu/Debian 等)
- **仮想化:** CPU の仮想化支援 (VT-x/AMD-V) が有効で、`/dev/kvm` が利用可能であること。
- **ツール:** Docker, SSH クライアント, `nc` (netcat)
- **ネットワーク:** ポート 2222 (SSH用) と 8006 (Web管理画面用) が利用可能であること。

## 3. 初回セットアップ手順

### Step 3.1: 保存用ディレクトリの作成
Windows の仮想ディスクデータを保存するディレクトリを作成します。
```bash
mkdir -p /home/shiro/rep2-win-data
```

### Step 3.2: ベース環境の構築
以下のコマンドで、インストール用のコンテナを起動します。
```bash
docker run -d --name rep2-win-base --device=/dev/kvm --cap-add NET_ADMIN \
  -v /home/shiro/rep2-win-data:/storage -e VERSION="server2022" \
  -p 8006:8006 -p 2222:22 dockur/windows
```
起動後、ブラウザで `http://localhost:8006` にアクセスします。
Windows のインストールが自動で進みます。デスクトップ画面が表示されるまで（数分〜十数分）待機してください。

### Step 3.3: Windows 内で OpenSSH サーバーを有効化
Windows のデスクトップが表示されたら、以下の操作を行います：
1. **設定 (Settings)** > **アプリ (Apps)** > **オプション機能 (Optional features)** を開く。
2. **機能の追加 (Add a feature)** をクリックし、`OpenSSH Server` を検索してインストールする。
3. **サービス (Services.msc)** を開き、`OpenSSH SSH Server` のスタートアップの種類を「自動」に変更し、サービスを開始する。

### Step 3.4: 公開鍵認証の設定 (パスワードレスログイン)
ホストOS (Linux) からパスワードなしでログインできるように設定します。
1. ホスト側で公開鍵をコピーします： `cat ~/.ssh/id_rsa.pub`
2. Windows 内で PowerShell を管理者として開き、以下を実行します：
```powershell
$authorizedKeysPath = "C:\Users\docker\.ssh\authorized_keys"
New-Item -ItemType Directory -Force -Path "C:\Users\docker\.ssh"
Set-Content -Path $authorizedKeysPath -Value "ここにコピーした公開鍵を貼り付け"
# パーミッション設定
icacls $authorizedKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" /grant "docker:F"
```
3. ホストからログインできるか確認します： `ssh -p 2222 docker@localhost`

### Step 3.5: コンテナの停止
準備ができたら、ベース環境のコンテナを停止して削除します。
```bash
docker stop rep2-win-base
docker rm rep2-win-base
```
※ `/home/shiro/rep2-win-data` にデータが残っている限り、この準備は一度きりで OK です。

## 4. テストの実行方法

1. Windows 版パッケージをビルドします：
   ```bash
   make windows
   ```
2. テストスクリプトを実行します：
   ```bash
   ./tests/test_dist_pkg_win.sh
   ```
   ※ ディスクデータが `/home/shiro/rep2-win-data` 以外にある場合は `--data-dir` で指定してください。

## 5. メンテナンス

- **評価版の期限切れ:** 180日を過ぎて Windows が起動しなくなった場合は、`/home/shiro/rep2-win-data` 内のファイルを削除し、Step 3 からやり直してください。
- **ディスク使用量:** 仮想ディスクは動的に拡張されますが、ホストの空き容量にご注意ください。
- **デバッグ:** `./tests/test_dist_pkg_win.sh --manual` を使用すると、テスト終了後もコンテナを維持し、`http://localhost:8006` で内部状態を確認できます。
