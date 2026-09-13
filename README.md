# Proxmox Server

Refreshing local cache on osx
```
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

Infrastructure-as-code (Terraform + Ansible) for a home Proxmox server.
Each service runs natively on its own Ubuntu VM and is reached through the
central nginx reverse proxy under private `*.lan` DNS names (see
`modules/dns/`). Deploy any VM with its `make deploy-<service>` target, e.g.
`make deploy-nginx`; all service IPs come from `proxmox.tfvars`.

## HTTPS for `*.lan` services (local CA)

`*.lan` is private DNS resolved by the local dnsmasq VM, so no public CA
(Let's Encrypt, ...) can ever issue a certificate for it. To get
browser-trusted HTTPS you run your own **CA root**, trust that root once per
client device, and sign a single **leaf certificate** that covers all the
`server_name`s nginx serves.

Current setup on the nginx VM (192.168.51.208):

| Item | Location | Lifetime |
|---|---|---|
| CA root key  | `/etc/lan-ca/ca.key` (0600, dir 0700) | 10 years |
| CA root cert | `/etc/lan-ca/ca.pem` | 10 years |
| Leaf SAN list | `/etc/lan-ca/domains` | — |
| Leaf cert | `/etc/nginx/certs/lan.crt` | 730 days |
| Leaf key   | `/etc/nginx/certs/lan.key` (0600) | 730 days |
| Renewal script | `/usr/local/bin/lan-cert-renew.sh` | — |
| Renewal timer | `lan-cert-renew.timer` (daily) | — |

nginx loads the leaf from the `http` context (`/etc/nginx/conf.d/30-ssl.conf`),
so every vhost inherits it. Plain `http://` is answered by the default server,
which `301`s to `https://`; HSTS is sent on all responses.

> The leaf is a **SAN certificate**, not a wildcard: `*.lan` would only match
> one label and would not cover `app.taiga.lan`. All 9 names are listed
> explicitly.

## Managing the certificate

Everything below is automated by `make deploy-nginx` (idempotent). The
commands are documented here so the process is reproducible by hand.

### Add a new domain

Append the name to the `lan_https_domains` list in
`modules/nginx/ansible.yml` and re-run `make deploy-nginx`. The renewal
script also detects the SAN drift daily and regenerates on its own, so even
without a deploy the new name is served within 24 h.

### Generate (or force-renew) the CA + leaf by hand

Run on the nginx VM as root (this is exactly what the playbook's
`cert_renew_script` does):

```bash
CA=/etc/lan-ca
CERT=/etc/nginx/certs
DOMAINS="app.kibana.lan app.elk.lan app.elastic.lan app.grafana.lan app.prometheus.lan app.jenkins.lan app.open-webui.lan ui-agent.llm.lan code-swarm-agent.llm.lan code-smith-agent.llm.lan app.taiga.lan"

mkdir -p "$CA" "$CERT" && chmod 700 "$CA" "$CERT"

# 1. CA root — generate ONCE; keep ca.key private (clients only ever see ca.pem)
openssl genrsa -out "$CA/ca.key" 4096
chmod 600 "$CA/ca.key"
openssl req -x509 -new -key "$CA/ca.key" -sha256 -days 3650 \
  -subj "/CN=LAN Home CA" -out "$CA/ca.pem"

# 2. Leaf key + signing request (CN is only a label; the SANs do the work)
openssl genrsa -out "$CERT/lan.key" 2048
chmod 600 "$CERT/lan.key"
openssl req -new -key "$CERT/lan.key" -subj "/CN=app.lan" -out "$CA/lan.csr"

# 3. SAN + usage extensions (one DNS: per name, comma-separated, no trailing comma)
{
  echo "subjectAltName=$(echo "$DOMAINS" | tr ' ' '\n' | sed 's/^/DNS:/' | awk '{if (NR>1) printf ","; printf "%s", $0}')"
  echo "keyUsage=digitalSignature,keyEncipherment"
  echo "extendedKeyUsage=serverAuth"
} > "$CA/san.cnf"

# 4. Sign the leaf with the CA root
openssl x509 -req -in "$CA/lan.csr" -CA "$CA/ca.pem" -CAkey "$CA/ca.key" \
  -CAcreateserial -days 730 -sha256 -extfile "$CA/san.cnf" -out "$CERT/lan.crt"

# 5. Reload nginx so it serves the new leaf
nginx -t && systemctl reload nginx
```

The daily timer runs `/usr/local/bin/lan-cert-renew.sh`, which regenerates the
leaf only when it is missing, expires within 60 days, or its SAN list drifts
from `/etc/lan-ca/domains` — then reloads nginx itself. To renew right now:
`sudo /usr/local/bin/lan-cert-renew.sh`.

> Gotcha: if the `subjectAltName` line ends up with a trailing comma (e.g. an
> empty entry from a trailing space in the domain list), OpenSSL 3 fails with
> `X509V3_parse_list:invalid null value`. Join with the `awk` shown above.

### Fetch the CA root to a client machine

Clients only need `ca.pem` (never the private key). From a machine on the LAN:

```bash
ssh nginx@192.168.51.208 'sudo cat /etc/lan-ca/ca.pem' > lan-ca.pem
openssl x509 -in lan-ca.pem -noout -subject -fingerprint -sha256
# subject= /CN=LAN Home CA
```

The gateway also serves the root at `http://<nginx_ip>/lan-ca.pem` (plain
http, excluded from the http→https redirect), guarded by a shared token:
the client must send the `x-lan-ca-token` header with the value of
`lan_ca_token` from `proxmox.tfvars` (anything else gets `403`):

```bash
curl -fs -H "x-lan-ca-token: $LAN_CA_TOKEN" \
  http://192.168.51.208/lan-ca.pem -o lan-ca.pem
```

The VM playbooks in this repo (e.g. `modules/open-webui`, which calls
`ui-agent.llm.lan` over TLS) receive the token as an extra var, fetch and install
the root automatically — the manual steps above are for machines outside
the repo.

## Trusting the CA root

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain lan-ca.pem
```

You will be asked for your password. Restart browsers afterwards (Chrome and
Safari cache the trust store). To undo:

```bash
sudo security delete-certificate -c "LAN Home CA" /Library/Keychains/System.keychain
```

### Linux — Debian / Ubuntu

```bash
sudo cp lan-ca.pem /usr/local/share/ca-certificates/lan-ca.crt   # .crt suffix is required
sudo update-ca-certificates
```

To undo: delete the file and re-run `sudo update-ca-certificates`.

### Linux — Fedora / RHEL

```bash
sudo cp lan-ca.pem /etc/pki/ca-trust/source/anchors/lan-ca.crt
sudo update-ca-trust
```

To undo: delete the file and re-run `sudo update-ca-trust`.

### Notes

- Firefox (recent versions) and Chromium use the system trust store on Linux,
  so the steps above are enough. If a browser still warns, import `ca.pem`
  directly into its own store (Firefox: Settings → Privacy & Security →
  Certificates → View Certificates → Authorities → Import).
- iOS/Android: AirDrop/send `ca.pem` to the device and open it ("Install
  Profile"); on iOS also enable full trust under Settings → General → About →
  Certificate Trust Settings.

### Node.js

Node ignores the OS trust store (it ships with Mozilla's bundled CA list), so
importing the CA on the OS is **not** enough for Node clients. Either:

```bash
# extra CA file (works everywhere, any Node >= 7) — export in ~/.zshrc
export NODE_EXTRA_CA_CERTS="$HOME/lan-ca.pem"

# or read the OS store instead (Node >= 22.17 — uses the keychain on macOS,
# /etc/ssl/certs on Linux)
export NODE_OPTIONS=--use-system-ca
```

Quick check:

```bash
NODE_EXTRA_CA_CERTS=~/lan-ca.pem node -e "require('https').get('https://app.taiga.lan/',r=>{console.log('OK',r.statusCode);r.resume()}).on('error',e=>console.log('FAIL:',e.message))"
```

For systemd-run Node units (e.g. taiga-events on the taiga VM), copy
`ca.pem` to the VM and set `Environment=NODE_EXTRA_CA_CERTS=/path/to/ca.pem`
in the unit instead. Never use `NODE_TLS_REJECT_UNAUTHORIZED=0` to silence
verification.

## Verifying

From a client that trusts the root — should succeed **without** `-k`:

```bash
curl --cacert lan-ca.pem -o /dev/null -w '%{http_code}\n' https://app.taiga.lan/
openssl s_client -connect app.taiga.lan:443 -servername app.taiga.lan -CAfile lan-ca.pem </dev/null 2>/dev/null | grep "Verify return code"
# Verify return code: 0 (ok)

# The leaf must carry every server_name as a SAN:
echo | openssl s_client -connect app.taiga.lan:443 -servername app.taiga.lan 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
```

Plain `http://` names should `301` to their `https://` counterpart, and every
HTTPS response should include `Strict-Transport-Security: max-age=31536000`.


## Deploying via make after infrastructure is deployed
eg. check @Makefile
```
make deploy-all
make deploy-exporters
make deploy-exporter HOST=jenkins
```
