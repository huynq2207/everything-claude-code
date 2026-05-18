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

## 7. Build image tại local (cho dev plugin)

```bash
cd <ecc-repo-root>
docker build -t ecc-dev:local -f docker/Dockerfile .

# test
docker run --rm -it ecc-dev:local claude --version
```

Sau khi sửa agents/commands → rebuild để bake vào image.

---

## 8. Đẩy image lên GitHub Container Registry (admin/maintainer)

```bash
# Login
echo "$GHCR_PAT" | docker login ghcr.io -u huynq2207 --password-stdin

# Tag & push
docker tag ecc-dev:local ghcr.io/huynq2207/everything-claude-code:latest
docker push ghcr.io/huynq2207/everything-claude-code:latest

# Tagged release
docker tag ecc-dev:local ghcr.io/huynq2207/everything-claude-code:v1.0.0
docker push ghcr.io/huynq2207/everything-claude-code:v1.0.0
```

Khuyến nghị: thêm GitHub Action `docker-publish.yml` để CI auto-build & push khi tag release.

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
- Có cần multi-arch (amd64 + arm64) không? (Mac M1/M2/M3 cần arm64)
- Workflow auto-build & push image khi merge `main` có cần dựng không?
