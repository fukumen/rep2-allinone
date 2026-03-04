# rep2-allinone

PHP-FPM、Caddy (Webサーバー)、そして rep2を統合したパッケージです。対応しているのは以下の通り。

- **Linux Debian系**:`.deb`
- **Linux RedHat系**:`.rpm`

## 特徴

- **All-in-One パッケージ**: PHP-FPM、Caddy (Webサーバー)、そして rep2 本体が1つのパッケージに統合されており、複雑なミドルウェアのインストールが不要です。
- **外部依存なし**: 静的リンクされた PHP バイナリを使用しているため、OSのPHPバージョンや他のシステム環境に影響されずに独立して動作します。
- **簡単かつ安全な運用**: 自動的に専用の非特権ユーザー (`rep2`) が作成され、標準の systemd サービスとして管理できるため、安全かつ簡単に運用できます。
- **常に最新**: [`rep2`](https://github.com/fukumen/p2-php) のソースコードが更新されると自動的に新しいパッケージがビルドされ、リポジトリ経由で手軽にアップデートできます。
- **パッケージサイズについて**: 静的リンクされた Caddy と PHP を内包しているため、パッケージのファイルサイズがやや大きくなります。（目安: Caddy 約39MB、PHP / PHP-FPM 各約11MB）

## インストールと起動

パッケージは公式の APT / DNF リポジトリからインストールすることをお勧めします。これにより、アップストリーム (`p2-php`) の更新に自動で追従できます。

### Ubuntu / Debian 系 (APT リポジトリ)

```bash
curl -fsSL https://fukumen.github.io/rep2-allinone/apt/fukumen.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/rep2-allinone-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/rep2-allinone-keyring.gpg] https://fukumen.github.io/rep2-allinone/apt ./" | sudo tee /etc/apt/sources.list.d/rep2-allinone.list

sudo apt update
sudo apt install rep2-allinone
```

### RHEL / CentOS / AlmaLinux 系 (DNF リポジトリ)

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/rep2-allinone.repo
[rep2-allinone]
name=rep2-allinone Repository
baseurl=https://fukumen.github.io/rep2-allinone/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://fukumen.github.io/rep2-allinone/rpm/fukumen.gpg.key
EOF

sudo dnf install rep2-allinone
```

### ⚠️アップデート時の注意事項

設定ファイルが格納されている `conf` ディレクトリ（`/var/lib/rep2-allinone/conf`）は、**自動でマージ・上書きされることはありません**。
アップストリームで設定項目の追加等があった場合は手動でマージする必要があります。

以下のコマンドで、パッケージ同梱の最新の conf と現在運用中の conf の差分を確認できます。差分を見て、追加された設定項目があれば適宜反映してください。

```bash
diff -ru /opt/rep2-allinone/p2-php/conf.orig /var/lib/rep2-allinone/conf | iconv -f SHIFT_JIS -t UTF-8
```

### インストール後の動作

インストールが完了すると、自動的に専用ユーザー (`rep2`) が作成され、systemd サービス (`rep2-allinone.service`) が起動します。Webブラウザからアクセス可能になります（デフォルトポート等は `/etc/rep2-allinone/Caddyfile` で設定されます）。

## システム構成 (インストール後)

- **プログラム本体**: `/opt/rep2-allinone` (PHPスクリプトなど、変更されないシステムファイル)
- **設定ファイル**: `/etc/rep2-allinone` (`Caddyfile` と `php-fpm.conf` はここに配置され、自由に編集可能です)
- **データ領域**: `/var/lib/rep2-allinone` (アプリの設定やログ、キャッシュデータはこちらに保存されます)
- **サービス名**: `rep2-allinone.service`

```bash
# ステータスの確認
sudo systemctl status rep2-allinone

# サービスの再起動
sudo systemctl restart rep2-allinone
```

## パッケージのバージョンについて

本パッケージのバージョン番号は、内包する各コンポーネントのバージョンがひと目でわかるように構成されています。
インストールされたパッケージのバージョン（例: `1.0.0-php8.5.3-caddy2.9.1+202403051200` 等）は、以下の情報を表しています。

- **`1.0.0`**: rep2-allinone 自体のベースバージョン
- **`php8.5.3` / `caddy2.9.1`**: 同梱されている PHP と Caddy のバージョン
- **`202403051200`**: 上流リポジトリ (`rep2`) の最新コミット日時 (JST)

※ OSのパッケージ命名規則により、RPM パッケージの場合は区切り文字がハイフンではなくドット (`.`) に変換されます。

---

## 開発者向け: パッケージのビルド

ご自身でカスタマイズしてパッケージをビルドする場合は、環境に応じて `dpkg-deb` または `rpmbuild` ( `rpm` パッケージ ) が必要です。

```bash
# Debian パッケージ (.deb) のビルド
make deb               # amd64 向け (デフォルト)
make ARCH=arm64 deb    # arm64 向け

# RPM パッケージ (.rpm) のビルド
make rpm               # x86_64 向け (デフォルト)
make ARCH=arm64 rpm    # aarch64 向け
```

ビルドが完了すると、`dist/` ディレクトリ配下に生成されます。

