Name:           rep2-allinone
Version:        %{_version}
Release:        %{_release}
Summary:        rep2-allinone (p2-php) with built-in Caddy and PHP-FPM
License:        MIT

%description
rep2-allinone integrates PHP-FPM, Caddy, and rep2 (p2-php) into a standalone package.
It provides a portable execution environment for rep2 with a dedicated user and systemd service.

%install
rm -rf %{buildroot}
cd %{_workspace}
make install DESTDIR=%{buildroot} ARCH=%{_orig_arch}

%pre
if ! id "rep2" &>/dev/null; then
    useradd --system --no-create-home -s /usr/sbin/nologin rep2
fi

%post
CONF_DIR="/etc/rep2-allinone"
SECRETS_FILE="$CONF_DIR/secrets.conf"

if [ ! -f "$SECRETS_FILE" ]; then
    SECRET_KEY=$(openssl rand -hex 32)
    echo "SECRET_KEY=$SECRET_KEY" > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
fi

mkdir -p /var/lib/rep2-allinone/{conf,data,ic}

chown -R rep2:rep2 /opt/rep2-allinone
chown -R rep2:rep2 /var/lib/rep2-allinone
chown -R root:rep2 /etc/rep2-allinone
chmod -R 755 /opt/rep2-allinone
chmod -R 750 /etc/rep2-allinone
chmod 640 /etc/rep2-allinone/Caddyfile
chmod 640 /etc/rep2-allinone/php-fpm.conf
chmod 640 "$SECRETS_FILE"

ln -sf /var/lib/rep2-allinone/conf /opt/rep2-allinone/p2-php/conf
ln -sf /var/lib/rep2-allinone/data /opt/rep2-allinone/p2-php/data
ln -sf /var/lib/rep2-allinone/ic /opt/rep2-allinone/p2-php/rep2/ic

systemctl daemon-reload
systemctl enable rep2-allinone || true
systemctl restart rep2-allinone || true

%preun
if [ $1 -eq 0 ]; then
    systemctl stop rep2-allinone || true
    systemctl disable rep2-allinone || true
    rm -f /opt/rep2-allinone/p2-php/conf
    rm -f /opt/rep2-allinone/p2-php/data
    rm -f /opt/rep2-allinone/p2-php/rep2/ic
fi

%files
/opt/rep2-allinone
%config(noreplace) /etc/rep2-allinone/Caddyfile
%config(noreplace) /etc/rep2-allinone/php-fpm.conf
/etc/systemd/system/rep2-allinone.service