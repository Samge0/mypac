// PAC (Proxy Auto-Config) 规则文件
// 规则：内网 IP / 本地域名直连，其他全部走上游代理
// {{PROXY_TARGET}} 由 server.py 在返回时动态替换
// 访问 http://<server>:<port> 即可获取（无需后缀）
//
// 设计原则：白名单制（默认 PROXY，仅明确内网走 DIRECT）
// 避免依赖 dnsResolve 判断，防止 DNS 污染导致被墙域名误判为直连。

function FindProxyForURL(url, host) {

    // ---------- 1. 本地主机名（不含点，如 nas、printer） ----------
    if (isPlainHostName(host)) return 'DIRECT';

    // ---------- 2. localhost / loopback ----------
    if (/^localhost$/i.test(host)) return 'DIRECT';
    if (/^127\./.test(host)) return 'DIRECT';
    if (host === '::1') return 'DIRECT';

    // ---------- 3. 常见内网域名后缀 ----------
    if (/\.(local|localdomain|internal|intra|lan|corp|home|private)(:\d+)?$/i.test(host)) {
        return 'DIRECT';
    }

    // ---------- 4. 纯 IP 地址的内网判断 ----------
    // 只对「直接用 IP 访问」的情况做判断（不依赖 DNS 解析）
    if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
        // 10.0.0.0/8
        if (isInNet(host, "10.0.0.0",  "255.0.0.0"))   return 'DIRECT';
        // 172.16.0.0/12
        if (isInNet(host, "172.16.0.0","255.240.0.0")) return 'DIRECT';
        // 192.168.0.0/16
        if (isInNet(host, "192.168.0.0","255.255.0.0")) return 'DIRECT';
        // 127.0.0.0/8 (loopback)
        if (isInNet(host, "127.0.0.0", "255.0.0.0"))   return 'DIRECT';
        // 169.254.0.0/16 (link-local)
        if (isInNet(host, "169.254.0.0","255.255.0.0")) return 'DIRECT';
        // 100.64.0.0/10 (Carrier-Grade NAT)
        if (isInNet(host, "100.64.0.0","255.192.0.0")) return 'DIRECT';
        // 0.0.0.0/8
        if (isInNet(host, "0.0.0.0",   "255.0.0.0"))   return 'DIRECT';
    }

    // ---------- 5. 其他所有情况 → 走代理 ----------
    // 注意：不再用 dnsResolve 反查域名 IP，避免 DNS 污染导致被墙域名误判直连
    return 'PROXY {{PROXY_TARGET}}';
}
