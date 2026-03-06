
## HTTPS 化と証明書の運用

本パッケージに同梱されている Caddy は、デフォルトで HTTP (:10088) に設定されています。
HTTPS 化については以下のガイドを参照してください。

- **[HTTPS 化と証明書の運用ガイド (doc/https.md)](doc/https.md)**



# HTTPS 化と証明書の運用ガイド

`rep2-allinone` は、デフォルトで HTTP (:10088) で動作するように設定されています。
セキュリティ向上のため、80/443 ポートをインターネットに公開せずに HTTPS 化（Let's Encrypt 等の証明書取得）が可能な **DNS-01 チャレンジ** による運用、または外部の Certbot を利用した運用を推奨します。

## セキュリティに関する重要な方針
`rep2` 本体を直接インターネット（80/443ポート）に公開して証明書を取得する「HTTP-01 チャレンジ」は、セキュリティ上の脆弱性を考慮し、本パッケージでは**非推奨**としています。以下の「ポートを開放しない方法」を選択してください。

---

## 方法 1: Caddy プラグインによる DNS-01 チャレンジ (推奨)
対応する DNS プロバイダー（Cloudflare, Route53, Google Cloud DNS 等）を利用している場合に最も簡単で確実な方法です。

### 1. カスタムバイナリの導入
標準の Caddy バイナリには DNS-01 チャレンジ用プラグインが含まれていません。以下の手順でカスタムバイナリを導入してください。

1. [Caddy公式サイト](https://caddyserver.com/download) から、必要なプラグイン（例: `dns.providers.cloudflare`）を含んだバイナリをダウンロードします。
2. ダウンロードしたバイナリを `/var/lib/rep2-allinone/custom-caddy` として配置し、実行権限を付与します。
   ```bash
   sudo mv caddy /var/lib/rep2-allinone/custom-caddy
   sudo chmod +x /var/lib/rep2-allinone/custom-caddy
   sudo chown rep2:rep2 /var/lib/rep2-allinone/custom-caddy
   ```
   ※ `/var/lib/rep2-allinone/custom-caddy` に実行可能なバイナリがある場合、パッケージ標準のバイナリよりも優先して使用されます。

### 2. 認証情報の設定
`/etc/rep2-allinone/secrets.conf` に API トークンなどを記述します。このファイルに記述された内容は環境変数として Caddy から参照できます。
```bash
# Cloudflare の場合
CLOUDFLARE_API_TOKEN=your_token_here
```

### 3. Caddyfile の編集
`/etc/rep2-allinone/Caddyfile` を編集し、ドメイン名と DNS チャレンジの設定を記述します。

```caddy
{
    email your-email@example.com
}

https://your-domain.example.com:443 {
    log {
        output stderr
    }
    tls {
        issuer acme {
            # Cloudflare の例
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}

            # 伝搬確認を 1.1.1.1 で行う（ローカルDNS環境での失敗を防ぐため）
            resolvers 1.1.1.1
        }
    }
    root * /opt/rep2-allinone/p2-php/rep2
    php_fastcgi 127.0.0.1:9000
    file_server

    @js_files {
        path *.js
    }
    header @js_files Content-Type "application/javascript; charset=Shift_JIS"
}
```

---

## 方法 2: 外部の Certbot を利用する (MyDNS 等)
Caddy プラグインが存在しないサービス（MyDNS.jp 等）を利用している場合や、すでにホスト側で Certbot を運用している場合に有効な方法です。

### 権限に関する注意点
`rep2-allinone` は専用の `rep2` ユーザーで動作するため、root 権限で生成・管理される `/etc/letsencrypt/live/` 以下の証明書ファイルを直接読み取ることができません。これを解決するために、Certbot のデプロイフックを利用して証明書ファイルをコピーします。

### 手順

1. **デプロイフックスクリプトの作成**
   `/etc/letsencrypt/renewal-hooks/deploy/rep2-allinone.sh` を以下の内容で作成します。
   ```bash
   #!/bin/sh
   # 証明書のコピー先 (rep2 ユーザーが読み書き可能な場所)
   DEST="/var/lib/rep2-allinone/certs"
   mkdir -p "$DEST"

   # 最新の証明書をコピー
   cp "$RENEWED_LINEAGE/fullchain.pem" "$DEST/fullchain.pem"
   cp "$RENEWED_LINEAGE/privkey.pem" "$DEST/privkey.pem"

   # 所有権と権限の設定
   chown -R rep2:rep2 "$DEST"
   chmod 600 "$DEST/privkey.pem"

   # 設定を反映 (Caddy のリロード)
   systemctl reload rep2-allinone
   ```
   作成後、実行権限を付与します。
   ```bash
   sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/rep2-allinone.sh
   ```

2. **初回コピーの実行**
   すでに証明書が取得済みの場合は、一度手動で上記のスクリプトを実行してファイルを配置してください。
   ```bash
   # RENEWED_LINEAGE 環境変数をシミュレートして実行
   sudo RENEWED_LINEAGE="/etc/letsencrypt/live/your-domain.example.com" /etc/letsencrypt/renewal-hooks/deploy/rep2-allinone.sh
   ```

3. **Caddyfile の設定**
   `/etc/rep2-allinone/Caddyfile` で、コピーした証明書ファイルを指定します。

```caddy
https://your-domain.example.com:443 {
    log {
        output stderr
    }
    tls /var/lib/rep2-allinone/certs/fullchain.pem /var/lib/rep2-allinone/certs/privkey.pem

    root * /opt/rep2-allinone/p2-php/rep2
    php_fastcgi 127.0.0.1:9000
    file_server

    @js_files {
        path *.js
    }
    header @js_files Content-Type "application/javascript; charset=Shift_JIS"
}
```

---

## 証明書の保存場所について
Caddy 自体が取得したデータは `/var/lib/rep2-allinone/caddy_data` に、外部からコピーした証明書は `/var/lib/rep2-allinone/certs` に保存されます。これらはパッケージのアップデート後も維持されます。
