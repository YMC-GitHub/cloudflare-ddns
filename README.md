# Cloudflare DDNS Client

A cross-platform dynamic DNS updater for Cloudflare written in Rust.

## Supported Platforms

- ✅ **Linux**: x86_64, AArch64 (glibc and musl)
- ✅ **Windows**: x86_64 (MSVC and GNU)
- ✅ **macOS**: x86_64, AArch64 (Apple Silicon)

## Quick Start

### Using Pre-built Binaries

Download the binary for your platform from the [Releases](https://github.com/ymc-github/cloudflare-ddns/releases) page.

### From Source

#### Prerequisites

- Rust 1.70+ (install from [rustup.rs](https://rustup.rs/))
- For cross-compilation: Docker (for `cross` tool)

#### Basic Build

```bash
# Clone the repository
git clone https://github.com/ymc-github/cloudflare-ddns.git
cd cloudflare-ddns

# Build for current platform
cargo build --release

# The binary will be at: target/release/cloudflare-ddns
```
#### Cross-compilation
Using cross (recommended):
```bash
# Install cross
cargo install cross --git https://github.com/cross-rs/cross

# Build for all supported platforms
chmod +x build-cross-platform.sh
./build-cross-platform.sh
```

Manual cross-compilation:
```bash
# Linux (musl - static linking)
rustup target add x86_64-unknown-linux-musl
cargo build --release --target x86_64-unknown-linux-musl

# Windows
rustup target add x86_64-pc-windows-msvc
cargo build --release --target x86_64-pc-windows-msvc

# macOS (from Linux)
rustup target add x86_64-apple-darwin
cargo build --release --target x86_64-apple-darwin
```


#### Platform-specific Notes

**Linux:**
- Use musl targets for maximum compatibility (static linking)
- glibc targets are smaller but require glibc on target system

**Windows:**
- MSVC target: Better performance, requires VC++ redistributable
- GNU target: No external dependencies, larger binary

**macOS:**
- Universal binaries not provided, choose appropriate architecture
- AArch64 for Apple Silicon, x86_64 for Intel Macs

## Binary Sizes

Typical binary sizes (release build):
- Linux (musl): ~4-5MB
- Linux (glibc): ~3-4MB  
- Windows: ~4-5MB
- macOS: ~4-5MB

## Features

- `native-tls` (default): Uses platform-native TLS (OpenSSL on Linux, Secure Transport on macOS, Schannel on Windows)
- `rustls`: Uses Rust TLS implementation (smaller binaries, no external dependencies)

Build with RustLS:
```bash
cargo build --release --no-default-features --features rustls
```

## Usage

See the main documentation for usage instructions.

## License

MIT OR Apache-2.0

## Demo
### run-log
```
zero:/mnt/d/code/rust/cloudflare-ddns# docker run -d --name cloudflare-ddns --restart unless-stopped --env-file .env $imagename
137ee5ca3f16a81a048a61ab908454cf59cc615761fa40ccc73b2631d36dfc03

zero:/mnt/d/code/rust/cloudflare-ddns# docker ps -f name=cloudflare-ddns
CONTAINER ID   IMAGE                     COMMAND                  CREATED          STATUS          PORTS     NAMES
137ee5ca3f16   cloudflare-ddns:scratch   "/app/cloudflare-ddns"   14 seconds ago   Up 11 seconds             cloudflare-ddns

zero:/mnt/d/code/rust/cloudflare-ddns# docker logs cloudflare-ddns
=========================Configuration=
✅ Platform: linux-x86_64
✅ Zone ID: xxxxxxxxxxxxxxxxxxxxxxxxx
✅ Record type: A
✅ Proxy enabled: false
✅ TTL: 120 seconds
✅ Host identifier: unknown-unix-host
✅ Network: cn
✅ Monitoring 3 domain(s): ["me.xx.top", "hn.xx.top", "ai.xx.top"]
======================Initial DDNS Update=
-------------------------get public IP-
✅ 2025-10-16 07:31:48 - Public IP address xx.xx.xxx.xx
---------------get DNS record for me.xx.top-
✅ 2025-10-16 07:31:49 - DNS record me.xx.top found
✅ 2025-10-16 07:31:49 - IP not changed (xx.xx.xxx.xx) for me.xx.top
---------------get DNS record for hn.xx.top-
✅ 2025-10-16 07:31:49 - DNS record hn.xx.top found
✅ 2025-10-16 07:31:49 - IP not changed (xx.xx.xxx.xx) for hn.xx.top
---------------get DNS record for ai.xx.top-
❌ 2025-10-16 07:31:49 - DNS record ai.xx.top not found, attempting to add
✅ 2025-10-16 07:31:50 - DNS record ai.xx.top added successfully
==============Starting update loop (300s interval)=
```