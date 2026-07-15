# L2TP/IPsec 部署与 sing-box 网关示例

### 服务端环境检测
```
for m in xfrm_user esp4 ppp_generic pppox l2tp_core l2tp_netlink l2tp_ppp; do
  modprobe "$m" 2>/dev/null && echo "OK $m" || echo "缺 $m"
done
```

### 常用命令

```bash
docker compose up -d
docker compose logs -f
docker exec l2tp accel-cmd show sessions
docker compose down
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
        "server": "223.5.5.5",
        "detour": "direct"
      },
      {
        "type": "https",
        "tag": "dns-remote",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "proxy",
        "domain_resolver": "dns-direct"
      },
      {
        "type": "local",
        "tag": "dns-local"
      }
    ],
    "rules": [
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "dns-direct"
      },
      {
        "source_ip_cidr": ["10.10.0.0/24"],
        "action": "route",
        "server": "dns-remote"
      }
    ],
    "final": "dns-remote",
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
      "route_exclude_address": ["10.10.0.0/24"]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "YOUR_ANYTLS_SERVER",
      "server_port": 443,
      "password": "YOUR_ANYTLS_PASSWORD",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5,
      "tls": {
        "enabled": true,
        "server_name": "YOUR_ANYTLS_SNI"
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
        "source_ip_cidr": ["10.10.0.0/24"],
        "invert": true,
        "action": "bypass"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": "geoip-cn",
        "action": "route",
        "outbound": "direct"
      },
      {
        "source_ip_cidr": ["10.10.0.0/24"],
        "action": "route",
        "outbound": "proxy"
      }
    ],
    "rule_set": [
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "update_interval": "1d"
      },
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "update_interval": "1d"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-direct"
    }
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/lib/sing-box/cache.db"
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

配置已启用 `auto_redirect`，**无需**额外添加 nftables SNAT；由 sing-box 透明代理接管即可。

**勿**对 `10.10.0.0/24` 单独配置直连公网网卡的 MASQUERADE，否则流量可能绕过 sing-box。

### systemd-resolved 注意

宿主机若启用 `systemd-resolved` 监听 `127.0.0.53:53`，可能与 TUN hijack 冲突。可选：

- 关闭 stub listener（`/etc/systemd/resolved.conf` 中 `DNSStubListener=no`），或
- 确保 `hijack-dns` 规则在 `route.rules` 第一条
