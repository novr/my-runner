# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository manages IaC (Infrastructure as Code) for disposable self-hosted GitHub Actions runners using [openai/tart](https://github.com/openai/tart) (Apple Silicon macOS virtualization). Runners are ephemeral — each job gets a fresh VM clone, which is destroyed after completion. Primary use case is iOS/macOS/Swift builds.

**Host requirement:** Apple Silicon Mac running macOS 13 (Ventura) or later.

## Architecture

```
Host Mac (Apple Silicon)
  └── tart (VM manager, uses Apple Virtualization.Framework)
        ├── Base image pool (pulled from GHCR)
        │     └── ghcr.io/cirruslabs/macos-<version>-xcode:latest
        └── Ephemeral runner VMs (cloned per job, deleted after)
              └── GitHub Actions runner process (--ephemeral flag)
```

### Ephemeral Runner Lifecycle

1. **Listen** — A host-side daemon/script polls GitHub Actions for queued jobs (via Runner Scale Set API or webhook).
2. **Clone** — `tart clone <base-image> <runner-name>` creates a fresh VM.
3. **Register** — GitHub JIT token is fetched and passed into the VM; runner registers with `--ephemeral` so it deregisters automatically after one job.
4. **Run** — VM executes the GitHub Actions job via SSH or `tart run` + startup script.
5. **Destroy** — `tart delete <runner-name>` cleans up the VM after completion.

### Key Images (cirruslabs, pulled from GHCR)

| Tag | Contents |
|-----|----------|
| `ghcr.io/cirruslabs/macos-tahoe-xcode:latest` | macOS 26 + Xcode (recommended) |
| `ghcr.io/cirruslabs/macos-sequoia-xcode:latest` | macOS 15 + Xcode |
| `ghcr.io/cirruslabs/macos-sonoma-xcode:latest` | macOS 14 + Xcode |

All base images use `admin`/`admin` credentials.

## Directory Structure

```
.
├── host/                         # Host machine provisioning
│   ├── setup.sh                  # Install prerequisites + pull base image
│   └── com.myrunner.pool.plist   # launchd service definition
├── runner/
│   ├── jit-config.sh             # Fetch single-use JIT config from GitHub API
│   └── bootstrap.sh              # Runs inside VM: installs runner, executes job, shuts down
├── scripts/
│   ├── spawn.sh                  # Spawn one ephemeral runner VM (blocking)
│   └── pool.sh                   # Keep POOL_SIZE runners alive at all times
├── images/                       # Custom VM image definitions (Packer templates) — future
├── .env.example                  # Configuration template
├── .env                          # Local config (gitignored)
└── Makefile                      # Entry points: setup / spawn / pool / clean
```

## Key Commands

```bash
# First-time setup
make setup

# Spawn a single runner (blocks until job completes)
make spawn

# Start the pool manager in the foreground
make pool

# Delete orphaned runner VMs
make clean

# Install/uninstall as a launchd background service
make plist-install
make plist-uninstall
```

### Tart CLI Reference

```bash
tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:latest <vm-name>
tart set <vm-name> --cpu 4 --memory 8192
tart run <vm-name> --no-graphics &
tart ip <vm-name> --wait 60
tart list
tart delete <vm-name>
tart push <vm-name> ghcr.io/<org>/<image>:<tag>
echo $GITHUB_TOKEN | tart login ghcr.io --username <user> --password-stdin
```

## GitHub Apps 認証

PAT ではなく GitHub Apps を使う。ユーザーアカウントに紐づかず、Installation Access Token（有効期限1時間）を自動取得するため長期トークン漏洩リスクがない。

### 必要な App 権限

| スコープ | 権限 |
|---|---|
| Organization self-hosted runners | Read & Write |

### セットアップ手順

```bash
# 1. Installation ID を調べる
gh api /orgs/{org}/installation --jq '.id'

# 2. .env に設定
GITHUB_APP_ID=<App ID>
GITHUB_APP_INSTALLATION_ID=<上記の値>
GITHUB_APP_PRIVATE_KEY_PATH=/etc/github-runner/private-key.pem   # リポジトリ外に置く
```

### トークン取得フロー（runner/github-token.sh）

```
秘密鍵(.pem) + App ID
    └── RS256署名 → JWT（有効10分）
          └── POST /app/installations/{id}/access_tokens
                └── Installation Access Token（有効1時間）→ API呼び出しに使用
```

### JIT Config（runner/jit-config.sh）

`jit-config.sh` は内部で `github-token.sh` を呼んでトークンを取得してから `generate-jitconfig` API を叩く。レスポンスの `runner_id` と `encoded_jit_config` を返す。`encoded_jit_config` は stdin 経由で VM 内の `bootstrap.sh` に渡し、`./run.sh --jitconfig <value>` で1ジョブ実行後にランナーが自動登録解除される。失敗時は `delete-runner.sh` で GitHub 上の登録を削除する。

offline の残骸掃除: `make prune-runners REPO=novr/Rin`

launchd（`make plist-install`）では keyring に届かないため、GitHub Apps 認証を使うこと。`gh auth token` フォールバックは対話利用向け。

## IaC Conventions

- **One VM per job** — never reuse a VM between jobs. Clone fresh, destroy after.
- **Image pinning** — pin images by digest or explicit version tag (e.g., `macos-sonoma-xcode:16.2`) in production; use `:latest` only for local testing.
- **Runner naming** — use a unique name per VM, e.g., `runner-$(uuidgen | tr '[:upper:]' '[:lower:]')`.
- **Resource sizing** — default: 4 vCPU, 8 GB RAM for standard iOS builds; 8 vCPU / 16 GB for large Xcode builds.
- **Secrets** — GitHub tokens and JIT configs must never be baked into VM images. Pass JIT config via stdin (never argv) so it does not appear in `ps`.
- **Cleanup guard** — always pair `tart clone` with a trap that stops (`kill` / `tart stop`) then deletes the VM.
- **Pool capacity** — count in-flight `spawn.sh` PIDs plus *running* VMs only; back off exponentially on consecutive spawn failures. Ctrl-C kills in-flight spawns.
- **SSH** — use `sshpass -e` (SSHPASS) and password-only auth; never put the VM password or JIT config on argv.
