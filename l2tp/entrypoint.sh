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
[ -n "${VPN_PUBLIC_IP:-}" ] && LEFT="$VPN_PUBLIC_IP"

cat > /etc/ipsec.d/l2tp-psk.conf <<EOF
conn l2tp-psk
	authby=secret
	pfs=no
	auto=add
	rekey=no
	type=transport
	keyexchange=ikev1
	left=${LEFT}
	leftprotoport=17/1701
	right=%any
	rightprotoport=17/%any
	ike=aes256-sha2;modp2048,aes128-sha1;modp2048
	esp=aes256-sha2,aes128-sha1
	encapsulation=yes
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

echo "[启动] libreswan + accel-ppp（L2TP/IPsec 预共享密钥）用户=${USER_NAME}"

ipsec pluto --config /etc/ipsec.conf --nofork --stderrlog &

exec accel-pppd -c /etc/accel-ppp/accel-ppp.conf
