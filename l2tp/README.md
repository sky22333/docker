# L2TP/IPsec

### 服务端环境检测
```
for m in xfrm_user esp4 ppp_generic pppox l2tp_core l2tp_netlink l2tp_ppp; do
  modprobe "$m" 2>/dev/null && echo "OK $m" || echo "缺 $m"
done
```

### Docker
```
docker run -d \
  --name l2tp \
  --restart unless-stopped \
  --network host \
  --privileged \
  --volume /lib/modules:/lib/modules:ro \
  --volume ./ipsec-nss:/var/lib/ipsec/nss \
  --volume ./vpn-logs:/var/log/accel-ppp \
  -e IPSEC_PSK="ChangeMeIPsecPSK!" \
  -e VPN_USER="vpnuser" \
  -e VPN_PASSWORD="ChangeMeNow!" \
  -e VPN_PUBLIC_IP="" \
  -e POOL_RANGE="10.10.0.2-254" \
  ghcr.io/sky22333/docker:l2tp
```

### 常用命令

```bash
docker logs -f l2tp
docker exec l2tp accel-cmd show sessions
```

---

## 附录：sing-box ≥ 1.14 示例

### 场景

L2TP 客户端地址池 `10.10.0.0/24`，仅该网段出站走 **AnyTLS** 代理；DNS 经 **`dns_mode: hijack`** 防泄漏。

```text
L2TP 客户端 (10.10.0.x)
  → l2tp 容器（host）
  → sing-box TUN（宿主机独立进程，auto_redirect）
  → AnyTLS 出站
```

### accel-ppp 需配合修改（启用 sing-box 时）

编辑 `docker/config/accel-ppp.conf`，将 DNS 改为网关地址（勿下发公网 DNS）：

```ini
[dns]
dns1=10.10.0.1
```

改完后：

```bash
docker compose down

docker compose up -d
```

### 生产配置 `config.json`（sing-box ≥ 1.14.0）

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "dns-direct",
        "server": "223.5.5.5"
      },
      {
        "type": "https",
        "tag": "dns-remote",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "proxy",
        "domain_resolver": "dns-direct"
      }
    ],
    "rules": [
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "action": "route",
        "server": "dns-remote"
      }
    ],
    "final": "dns-direct",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": ["172.19.0.1/30"],
      "mtu": 1500,
      "stack": "mixed",
      "dns_mode": "hijack",
      "dns_address": ["172.19.0.2"],
      "auto_route": true,
      "auto_redirect": true,
      "strict_route": true,
      "route_exclude_address": ["10.10.10.0/24"]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "8.8.8.8",
      "server_port": 8443,
      "password": "iAq43123123",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5,
      "tls": {
        "enabled": true,
        "server_name": "bing.com",
        "insecure": true
      },
      "domain_resolver": "dns-direct"
    }
  ],
  "route": {
    "rules": [
      {
        "port": [53],
        "action": "hijack-dns"
      },
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "invert": true,
        "action": "bypass"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "action": "route",
        "outbound": "proxy"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-direct"
    }
  }
}
```

### 配置要点

| 配置项 | 作用 |
|--------|------|
| `dns_mode: "hijack"` | 1.14+ TUN 默认 DNS 劫持；配合 `auto_redirect` 对 53 端口 DNAT 到 `dns_address` |
| `dns_address: ["172.19.0.2"]` | 劫持目标；显式设置时需保留 `hijack-dns` 路由规则 |
| `port: [53] / hijack-dns` | 路由规则置顶，防止 DNS 绕行 |
| `source_ip_cidr` + `bypass` | 仅 L2TP 网段走代理，宿主机自身流量直连 |
| `type: anytls` | 出站协议；`server` / `server_port` / `password` / `tls` 均为必填 |
| `domain_resolver` | 1.14 出站域名为 FQDN 时必须指定（用于解析 AnyTLS 服务器） |


### 宿主机网络补充

```bash
# 转发（与 VPN 容器 entrypoint 一致，宿主机也需开启）
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
```
