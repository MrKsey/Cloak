# Cloak (Optimized Fork)

[README на русском](README_ru.md)

[![Build and test](https://github.com/MrKsey/Cloak/actions/workflows/build.yml/badge.svg)](https://github.com/MrKsey/Cloak/actions)
[![Release](https://github.com/MrKsey/Cloak/actions/workflows/release.yml/badge.svg)](https://github.com/MrKsey/Cloak/releases)

Cloak is a [pluggable transport](https://datatracker.ietf.org/meeting/103/materials/slides-103-pearg-pt-slides-01) that enhances traditional proxy tools (Shadowsocks, OpenVPN, etc.) to evade sophisticated censorship and deep packet inspection.

This is an **optimized fork** of [cbeuw/Cloak](https://github.com/cbeuw/Cloak) focused on improving throughput and reducing latency through targeted performance optimizations.

---

## Performance Optimizations

This fork implements several key optimizations that significantly improve speed:

### 1. Eliminated per-frame `crypto/rand` syscalls
The original code called `crypto/rand.Read` on every frame to generate padding and nonce bytes — an expensive syscall. This fork replaces it with a per-goroutine ChaCha8 PRNG pool seeded with cryptographic randomness, eliminating syscalls in the hot path while maintaining security.

### 2. Skipped unnecessary random generation for encrypted frames
When AEAD encryption is enabled, the last bytes of the random region are overwritten by the AEAD authentication tag. The original code generated random bytes that were immediately discarded. This fork only generates random bytes when they are actually needed (padding for the first 5 frames, or nonce for plain mode).

### 3. Buffer pool for connection copying
The `Copy` function now uses a `sync.Pool` for its 32 KiB buffer instead of allocating per call, reducing GC pressure with many concurrent connections.

### 4. Fixed TLS write buffer sizing
Increased the TLS connection write buffer pool capacity to match the maximum TLS record size (RFC 8446 §5.2), eliminating buffer reallocations for large frames.

### Benchmark Results

Obfuscation throughput improvements (1 KiB frames, single-threaded):

| Encryption | Original | Optimized | Speedup |
|---|---|---|---|
| plain | 1,699 MB/s | 4,065 MB/s | **2.4x** |
| AES-128-GCM | 1,103 MB/s | 1,864 MB/s | **1.7x** |
| AES-256-GCM | 1,034 MB/s | 1,665 MB/s | **1.6x** |
| ChaCha20-Poly1305 | 831 MB/s | 1,174 MB/s | **1.4x** |

End-to-end integration improvements (16 KiB frames):

| Encryption | Original | Optimized | Improvement |
|---|---|---|---|
| plain | 1,710 MB/s | 1,818 MB/s | +6.3% |
| AES-128-GCM | 1,395 MB/s | 1,500 MB/s | +7.5% |
| ChaCha20-Poly1305 | 876 MB/s | 1,016 MB/s | +15.9% |

Latency reduced by 9-35% across all encryption methods.

---

## Quick Start

To quickly deploy Cloak with Shadowsocks on a server, you can run this [script](https://github.com/HirbodBehnam/Shadowsocks-Cloak-Installer/blob/master/Cloak2-Installer.sh) written by @HirbodBehnam.

## Build

### From source

```bash
git clone https://github.com/MrKsey/Cloak
cd Cloak
go get ./...
make
```

Built binaries will be in the `build` folder.

### Cross-compilation

```bash
# Linux amd64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" ./cmd/ck-client
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" ./cmd/ck-server

# Linux arm64
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" ./cmd/ck-client
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" ./cmd/ck-server

# Windows amd64
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" ./cmd/ck-client
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" ./cmd/ck-server
```

### Pre-built binaries

Download the latest release for your platform from the [Releases page](https://github.com/MrKsey/Cloak/releases).

Available targets:
- `ck-client-linux-amd64`
- `ck-client-linux-arm64`
- `ck-client-windows-amd64.exe`
- `ck-server-linux-amd64`
- `ck-server-linux-arm64`
- `ck-server-windows-amd64.exe`

---

## Configuration

Examples of configuration files can be found under `example_config` folder.

### Server

`RedirAddr` — the redirection address when the incoming traffic is not from a Cloak client. Ideally a major website allowed by the censor (e.g. `www.bing.com`).

`BindAddr` — a list of addresses Cloak will bind and listen to (e.g. `[":443",":80"]`).

`ProxyBook` — an object whose key is the name of the ProxyMethod used on the client-side (case-sensitive). Its value is an array whose first element is the protocol, and the second element is an `IP:PORT` string of the upstream proxy server.

Example:
```json
{
  "ProxyBook": {
    "shadowsocks": ["tcp", "localhost:51443"],
    "openvpn": ["tcp", "localhost:12345"]
  }
}
```

`PrivateKey` — the static curve25519 Diffie-Hellman private key encoded in base64.

`BypassUID` — a list of UIDs that are authorised without any bandwidth or credit limit restrictions.

`AdminUID` — the UID of the admin user in base64. Leave empty if you only add users to `BypassUID`.

`DatabasePath` — path to `userinfo.db` for storing user usage info. Leave empty if you only use `BypassUID`.

`KeepAlive` — TCP KeepAlive seconds for the upstream proxy connection. Zero or negative disables it. Default: 0.

### Client

`UID` — your UID in base64.

`Transport` — `direct` or `CDN`.

`PublicKey` — the static curve25519 public key in base64, given by the server admin.

`ProxyMethod` — must match one of the entries in the server's `ProxyBook`.

`EncryptionMethod` — `plain`, `aes-256-gcm`, `aes-128-gcm`, or `chacha20-poly1305`. **Only use `plain` if your underlying proxy already provides encryption and authentication.**

`ServerName` — the domain you want your ISP to think you are visiting. Use `random` to randomize per connection.

`AlternativeNames` — array of domains to shuffle between for each new connection.

`CDNOriginHost` — origin server domain under CDN mode. Only effective when `Transport` is `CDN`.

`CDNWsUrlPath` — URL path for WebSocket requests under CDN mode. Defaults to `/`.

`NumConn` — number of underlying TCP connections. Default: 4. Set to 0 for singleplex mode.

`BrowserSig` — browser signature to emulate: `chrome`, `firefox`, or `safari`.

`KeepAlive` — TCP KeepAlive seconds for the Cloak server connection. Default: 0 (disabled).

`StreamTimeout` — seconds Cloak waits for an incoming connection to send data before closing it.

## Setup

### Server Setup

1. Install at least one underlying proxy server (e.g. OpenVPN, Shadowsocks).
2. Download the [latest release](https://github.com/MrKsey/Cloak/releases) or build from source.
3. Run `ck-server -key`. The **public** key goes to users, the **private** key stays secret.
4. (Skip if only using unrestricted users) Run `ck-server -uid` to generate an `AdminUID`.
5. Copy `example_config/ckserver.json` to a desired location. Set `PrivateKey` and `AdminUID`.
6. Configure your proxy servers to listen on localhost. Edit `ProxyBook` accordingly.
7. Run `sudo ck-server -c <path to ckserver.json>`.

#### Adding Users

**Unrestricted users:** Run `ck-server -uid` and add the UID to `BypassUID`.

**Users with bandwidth/credit controls:**
1. Ensure `AdminUID` and `DatabasePath` are set in `ckserver.json`.
2. On the client, run `ck-client -s <IP> -l <local-port> -a <AdminUID> -c <path-to-ckclient.json>` to enter admin mode.
3. Visit [Cloak-panel](https://cbeuw.github.io/Cloak-panel) to manage users.

### Client Setup

1. Install the underlying proxy client matching the server.
2. Download the [latest release](https://github.com/MrKsey/Cloak/releases) or build from source.
3. Obtain the public key and your UID from the server administrator.
4. Copy `example_config/ckclient.json` and enter your `UID` and `PublicKey`. Set `ProxyMethod` to match the server's `ProxyBook`.
5. Run `ck-client -c <path-to-ckclient.json> -s <server-ip>`.

---

## License

Cloak is licensed under the GPLv3. See [LICENSE](LICENSE) for details.
