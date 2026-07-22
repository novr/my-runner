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

## Directory Structure (intended)

```
.
├── host/           # Host machine provisioning (Ansible / shell)
├── images/         # Custom VM image definitions (Packer templates)
├── runner/         # Runner registration, JIT token fetching, lifecycle scripts
├── scripts/        # Helper scripts (clone, run, delete, health-check)
└── workflows/      # Example GitHub Actions workflow files for testing
```

## Key Commands

### Tart CLI

```bash
# Install tart
brew install openai/tools/tart

# Pull a base image
tart clone ghcr.io/cirruslabs/macos-tahoe-xcode:latest <vm-name>

# Configure VM resources
tart set <vm-name> --cpu 4 --memory 8192

# Run VM (headless)
tart run <vm-name> --no-graphics &

# Get VM IP (poll until ready)
tart ip <vm-name> --wait 60

# SSH into VM
ssh -o StrictHostKeyChecking=no admin@$(tart ip <vm-name>)

# Run a script inside VM
sshpass -p admin ssh -o StrictHostKeyChecking=no admin@$(tart ip <vm-name>) < script.sh

# List local VMs
tart list

# Delete VM
tart delete <vm-name>

# Push custom image to registry
tart push <vm-name> ghcr.io/<org>/<image>:<tag>
```

### GitHub Actions Runner (inside VM)

```bash
# Register ephemeral runner with JIT token
./config.sh --url https://github.com/<org> \
  --token <JIT_TOKEN> \
  --name <runner-name> \
  --labels macos,tart,xcode \
  --ephemeral \
  --unattended

# Start runner
./run.sh
```

### OCI Registry Auth

```bash
# Login to GHCR
echo $GITHUB_TOKEN | tart login ghcr.io --username <user> --password-stdin
```

## GitHub JIT Token

Fetch a Just-In-Time runner registration token (single-use, for `--ephemeral`):

```bash
# Org-level
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/orgs/<org>/actions/runners/generate-jit-config \
  -d '{"name":"<runner>","runner_group_id":1,"labels":["macos","tart"],"work_folder":"_work"}'
```

The response contains `encoded_jit_config` — pass it to `./run.sh` instead of using `config.sh`.

## IaC Conventions

- **One VM per job** — never reuse a VM between jobs. Clone fresh, destroy after.
- **Image pinning** — pin images by digest or explicit version tag (e.g., `macos-sonoma-xcode:16.2`) in production; use `:latest` only for local testing.
- **Runner naming** — use a unique name per VM, e.g., `runner-$(uuidgen | tr '[:upper:]' '[:lower:]')`.
- **Resource sizing** — default: 4 vCPU, 8 GB RAM for standard iOS builds; 8 vCPU / 16 GB for large Xcode builds.
- **Secrets** — GitHub tokens and JIT configs must never be baked into VM images. Inject at runtime via SSH or environment variables.
- **Cleanup guard** — always pair `tart clone` with a `trap "tart delete <name>" EXIT` in scripts to prevent orphaned VMs.
