# Docker Setup Guide

> Cách dùng **Docker image dựng sẵn** chứa Claude Code + ECC agents.
> Không cần cài Node, không cài CLI, không clone plugin — chỉ cần Docker.

---

## 1. Khi nào dùng Docker

| Tình huống | Khuyến nghị |
|---|---|
| Dev mới onboard, máy chưa setup gì | ✅ Docker |
| Máy không dùng được Node/CLI (Windows IT lock) | ✅ Docker |
| Cần môi trường review nhất quán cho cả team | ✅ Docker |
| Đã có Claude Code chạy native, quen workflow | ❌ Cứ dùng native ([local-agent-setup-guide.md](local-agent-setup-guide.md)) |
| CI/CD pipeline | ❌ Dùng GitHub Actions ([agent-setup-guide.md](agent-setup-guide.md)) |

---

## 2. Yêu cầu

- **Docker Desktop** (macOS/Windows) hoặc Docker Engine (Linux), version >= 20.10
- 4 GB RAM available cho container
- ~ 1.5 GB disk cho image

Verify:

```bash
docker --version
docker compose version
```

---

## 3. Pull image dựng sẵn

```bash
docker pull ghcr.io/huynq2207/everything-claude-code:latest
```

Image kèm:
- Node 20 + Claude Code CLI
- `git`, `gh`, `jq`, `ripgrep`, `python3`
- ECC agents/commands/skills/rules được symlink sẵn vào `/root/.claude/`

Verify (in version các tool bên trong):

```bash
docker run --rm ghcr.io/huynq2207/everything-claude-code:latest \
  bash -c "claude --version && git --version && gh --version | head -1"
```

---

## 4. Chạy lần đầu (interactive)

### 4A. Dùng wrapper script (đơn giản nhất)

```bash
# Clone wrapper 1 lần
curl -fsSL https://raw.githubusercontent.com/huynq2207/everything-claude-code/main/docker/claude-docker.sh \
  -o /usr/local/bin/claude-docker
chmod +x /usr/local/bin/claude-docker

# Đứng tại repo project của bạn
cd <your-project>
claude-docker            # mở bash trong container, project mount tại /workspace
# bên trong:
claude                   # mở Claude Code REPL
```

### 4B. Dùng `docker compose`

```bash
git clone https://github.com/huynq2207/everything-claude-code.git ~/ecc
cd <your-project>
PROJECT_DIR=$PWD docker compose -f ~/ecc/docker/docker-compose.yml run --rm claude
```

### 4C. Plain `docker run`

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -v "$HOME/.claude/credentials.json:/root/.claude/credentials.json:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$HOME/.gitconfig:/root/.gitconfig:ro" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  ghcr.io/huynq2207/everything-claude-code:latest \
  bash
```

---

## 5. Authentication trong Docker

### 5A. OAuth team license (nếu host đã login)

Trên **host** máy, login 1 lần:

```bash
claude /login    # cần cài Claude Code native trên host để OAuth flow
```

Sau đó `~/.claude/credentials.json` được tạo. Wrapper script tự mount file này vào container → các session sau **không cần re-auth**.

> Lý do phải login trên host trước: OAuth flow cần browser callback → container không có browser. Trick mount credential file là cách sạch nhất.

### 5B. API key (BYOK)

Không cần Claude Code trên host. Chỉ cần export key:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
claude-docker claude       # key được forward vào container
```

Persist:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc
```

### 5C. So sánh

| | OAuth (5A) | API key (5B) |
|---|---|---|
| Cần Claude Code trên host? | ✅ (để login 1 lần) | ❌ |
| Billing | Team plan | Per-token |
| Auto-refresh token | ✅ | n/a |
| Phù hợp cho CI Docker | ❌ | ✅ |

---

## 6. Workflow hằng ngày

```bash
cd <your-project>
claude-docker                       # vào container
# bên trong:
claude /code-review                 # review uncommitted diff
claude /security-scan               # AgentShield scan
claude /plan "Add SSO connector"    # plan feature mới
exit                                # rời container
```

Container ephemeral — exit là xoá. Project mount nên file edit vẫn lưu trên host.

---

## 7. Build image tại local

### 7A. Single-arch (chỉ kiến trúc máy host)

```bash
cd <ecc-repo-root>
docker build -t ecc-dev:local -f docker/Dockerfile .

# test
docker run --rm -it ecc-dev:local claude --version
```

Build ra image cho đúng kiến trúc của máy bạn (M1/M2/M3 → arm64, Intel/Linux server → amd64).

### 7B. Multi-arch (amd64 + arm64) — dùng `buildx`

Lý do cần multi-arch:
- Mac Apple Silicon (M1/M2/M3/M4) chạy **arm64**
- Linux servers / Windows / Intel Mac chạy **amd64**
- Image single-arch sẽ chạy được nhưng qua emulation → chậm 3–10×

Dùng wrapper:

```bash
# Build local (xuất OCI tar — verify multi-arch không lỗi)
./docker/build-multi-arch.sh

# Build và push thẳng lên registry
IMAGE=ghcr.io/huynq2207/everything-claude-code TAG=v1.0.0 PUSH=1 \
  ./docker/build-multi-arch.sh
```

Thủ công bằng buildx:

```bash
# Setup builder 1 lần
docker buildx create --name ecc-builder --use --bootstrap
docker run --privileged --rm tonistiigi/binfmt --install all   # cross-arch emulation

# Build + push
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/huynq2207/everything-claude-code:latest \
  -f docker/Dockerfile \
  --push .
```

Verify manifest sau khi push:

```bash
docker buildx imagetools inspect ghcr.io/huynq2207/everything-claude-code:latest
# expected:
#   Manifests:
#     linux/amd64
#     linux/arm64
```

Sau khi sửa agents/commands → rebuild để bake vào image.

---

## 8. Auto-publish qua GitHub Actions (Recommended)

Repo đã có workflow [.github/workflows/docker-publish.yml](../.github/workflows/docker-publish.yml).

Trigger:
- Push `main` → tag `:latest` + `:main`
- Push tag `v*` (vd `v1.2.3`) → tag `:v1.2.3` + `:1.2` + `:1`
- Manual `workflow_dispatch`

Output: image multi-arch (amd64 + arm64) tự build qua QEMU + buildx, push lên GHCR.

Setup (1 lần):

1. Cấp quyền packages cho GH Actions:
   - Settings → Actions → General → Workflow permissions → "Read and write"
2. Đảm bảo `GITHUB_TOKEN` có scope `packages: write` (workflow đã khai báo).
3. Sau lần publish đầu tiên: Settings → Packages → `everything-claude-code` → Change visibility (Public / Internal).

Tag release để build:

```bash
git tag v1.0.0
git push origin v1.0.0
# → workflow tự chạy, image có ở ghcr.io/huynq2207/everything-claude-code:v1.0.0
```

Push thủ công (nếu không dùng CI):

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u huynq2207 --password-stdin
PUSH=1 TAG=latest ./docker/build-multi-arch.sh
```

---

## 9. Troubleshooting

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `permission denied` khi mount SSH | Selinux/MacOS quyền | Thêm `:Z` vào volume mount (`-v "$HOME/.ssh:/root/.ssh:ro,Z"`) |
| `git push` fail trong container | SSH agent không forward | Mount `SSH_AUTH_SOCK`: `-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent` |
| Claude không thấy agents | Image cũ, chưa rebuild | `docker pull ghcr.io/.../everything-claude-code:latest` |
| Credentials không mount | File chưa tồn tại trên host | Login trên host trước (`claude /login`) |
| Slow first run | Pull image lần đầu | 1 lần thôi, sau đó cached |
| `gh` không auth | Token chưa forward | `-e GH_TOKEN="$GH_TOKEN"` hoặc `gh auth login` trong container |
| File edit không persist | Project chưa mount đúng | Verify `$PROJECT_DIR` hoặc dùng `$PWD` |

---

## 10. Bảo mật

- Image dùng `node:20-bookworm-slim` — base có CVE → cập nhật định kỳ
- Chạy `docker scan ghcr.io/huynq2207/everything-claude-code:latest` weekly
- **Không** bake API key / credentials vào image (đã đảm bảo trong Dockerfile)
- Mount mọi credential **read-only** (`:ro`)
- Container chạy user `root` mặc định — OK cho dev tool, không khuyến nghị cho production workload

---

## 11. Liên kết

- [local-agent-setup-guide.md](local-agent-setup-guide.md) — setup native (không Docker)
- [agent-setup-guide.md](agent-setup-guide.md) — project-level + CI/CD setup
- [sdlc-overview.md](sdlc-overview.md) — quy trình tổng
- Source: `docker/Dockerfile`, `docker/docker-compose.yml`, `docker/claude-docker.sh`

---

## Câu hỏi cần làm rõ

- Team có GitHub Container Registry quota chưa? Hay dùng Docker Hub / private registry nội bộ?
- Image base có cần đổi sang `distroless` / `alpine` để giảm CVE surface không?
- Cần thêm `linux/arm64/v8` riêng cho Raspberry Pi / ARM servers ngoài `linux/arm64` không?
- Có nên build thêm Windows container image không? (hiện chỉ build linux/*)
