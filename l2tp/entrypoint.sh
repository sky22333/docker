#!/bin/sh
set -eu

mkdir -p /var/run/pluto /var/lib/ipsec/nss /var/log/accel-ppp /var/lib/accel-ppp /etc/ipsec.d /etc/ppp

USER_NAME="${VPN_USER:-vpnuser}"
USER_PASS="${VPN_PASSWORD:-ChangeMeNow!}"
POOL_RANGE="${POOL_RANGE:-10.10.0.2-254}"
printf '"%s" * "%s" %s\n' "$USER_NAME" "$USER_PASS" "$POOL_RANGE" > /etc/ppp/chap-secrets
chmod 600 /etc/ppp/chap-secrets

PSK="${IPSEC_PSK:-ChangeMeIPsecPSK!}"
printf '%%any  %%any  : PSK "%s"\n' "$PSK" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets

LEFT="%defaultroute"
LEFT_ID="%defaultroute"
PUBLIC_IP="${VPN_PUBLIC_IP:-}"
if [ -z "$PUBLIC_IP" ]; then
  echo "[入口] 未设置 VPN_PUBLIC_IP，正在获取公网 IP (ipinfo.io)..."
  PUBLIC_IP="$(curl -fsS --connect-timeout 5 --max-time 10 https://ipinfo.io/ip 2>/dev/null | tr -d '[:space:]' || true)"
fi

case "$PUBLIC_IP" in
  *[!0-9.]*|"") PUBLIC_IP="" ;;
esac
if [ -n "$PUBLIC_IP" ]; then
  LEFT="%defaultroute"
  LEFT_ID="$PUBLIC_IP"
  echo "[入口] 服务端公网 IP=${PUBLIC_IP}（left=%defaultroute leftid=${PUBLIC_IP}）"
else
  echo "[入口] 警告：未能确定公网 IP，IPsec left/leftid 使用 %defaultroute" >&2
fi

cat > /etc/ipsec.d/l2tp-psk.conf <<EOF
conn l2tp-psk
	authby=secret
	pfs=no
	auto=add
	rekey=no
	type=transport
	keyexchange=ikev1
	left=${LEFT}
	leftid=${LEFT_ID}
	leftprotoport=17/1701
	right=%any
	rightprotoport=17/%any
	ike=aes256-sha2_256;modp2048,aes128-sha1;modp2048
	phase2alg=aes256-sha2_256,aes128-sha1
	encapsulation=yes
	dpddelay=30
	dpdtimeout=120
	dpdaction=clear
EOF

if [ ! -f /var/lib/ipsec/nss/cert9.db ]; then
  echo "[入口] 正在初始化 NSS 证书库..."
  ipsec initnss
fi

need_mod() {
  name="$1"
  if [ -d "/sys/module/$name" ] || grep -q "^${name} " /proc/modules 2>/dev/null; then
    echo "[模块] ${name} 已就绪"
    return 0
  fi
  if modprobe "$name"; then
    echo "[模块] 已加载 ${name}"
    return 0
  fi
  echo "[入口] 致命错误：缺少必需内核模块 ${name}" >&2
  exit 1
}

need_mod xfrm_user
need_mod esp4
need_mod ppp_generic
need_mod pppox
need_mod l2tp_core
need_mod l2tp_netlink
need_mod l2tp_ppp

if ! echo 1 > /proc/sys/net/ipv4/ip_forward; then
  echo "[入口] 致命错误：无法开启 IPv4 转发（net.ipv4.ip_forward）" >&2
  exit 1
fi

for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
  echo 0 > "$f" 2>/dev/null || true
done

echo "[启动] libreswan + accel-ppp（L2TP/IPsec 预共享密钥）用户=${USER_NAME} left=${LEFT} leftid=${LEFT_ID}"

ipsec pluto --config /etc/ipsec.conf --nofork --stderrlog &
PLUTO_PID=$!

ok=0
i=0
while [ "$i" -lt 30 ]; do
  if kill -0 "$PLUTO_PID" 2>/dev/null \
    && ipsec briefconnectionstatus 2>/dev/null | grep -q 'loaded [1-9]'; then
    ok=1
    break
  fi
  i=$((i + 1))
  sleep 0.2
done

if [ "$ok" -ne 1 ]; then
  echo "[入口] 致命错误：IPsec 连接未加载（检查 /etc/ipsec.d/l2tp-psk.conf）" >&2
  ipsec briefconnectionstatus 2>/dev/null || true
  kill "$PLUTO_PID" 2>/dev/null || true
  exit 1
fi

echo "[IPsec] 连接已加载："
ipsec briefconnectionstatus 2>/dev/null || true

exec accel-pppd -c /etc/accel-ppp/accel-ppp.conf
