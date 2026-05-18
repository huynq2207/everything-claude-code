# Local Agent Setup Guide

> Hướng dẫn cài Claude Code + agents `code-reviewer` & `security-reviewer` trên máy cá nhân của dev/tech lead.
> Mục tiêu: chạy `/code-review` và `/security-scan` ngay tại local trước khi push, bắt lỗi sớm — không phải đợi CI.

---

## 1. Yêu cầu hệ thống

| Component | Version | Check |
|---|---|---|
| Node.js | >= 18 | `node -v` |
| Git | >= 2.30 | `git --version` |
| `gh` (GitHub CLI) | bất kỳ | `gh --version` |
| Anthropic API key | active | console.anthropic.com → Settings → API Keys |

macOS: cài qua `brew`. Linux/Windows: nvm hoặc installer chính thức.

---

## 2. Cài Claude Code CLI

### macOS / Linux

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

### Windows (PowerShell)

```powershell
iwr https://claude.ai/install.ps1 -useb | iex
```

### Verify

```bash
claude --version
# expected: claude-code x.y.z
```

---

## 3. Xác thực — chọn 1 trong 2 cách

Claude Code hỗ trợ 2 cách xác thực. **Khuyến nghị dùng OAuth team license** (3A) nếu công ty đã mua Team/Enterprise plan — không cần quản lý API key cá nhân, billing tập trung.

### 3A. OAuth subscription (Team / Enterprise license) — Recommended

**Điều kiện**:
- Công ty đã có Claude Team / Enterprise plan
- Admin đã invite email công ty của bạn vào team workspace (qua console.anthropic.com)
- Bạn đã accept invite trong email

**Đăng nhập**:

```bash
# Lần đầu: chỉ cần chạy claude, sẽ tự mở trình duyệt OAuth
claude
# hoặc explicit:
claude /login
```

Flow:
1. Terminal in URL → tự mở browser
2. Đăng nhập bằng email công ty (SSO nếu công ty bật)
3. Chọn workspace team được hiển thị
4. Authorize Claude Code → token lưu vào `~/.claude/credentials.json`
5. Quay lại terminal → session ready

**Verify**:

```bash
claude /status
# expected:
#   Auth: oauth
#   Workspace: <your-team-name>
#   Plan: Team (or Enterprise)
```

**Đổi workspace** (nếu thuộc nhiều team):

```bash
claude /logout
claude /login
# chọn workspace khác
```

**Lưu ý quan trọng**:
- Quota dùng theo plan team, không bị tính tiền cá nhân
- Token tự refresh, không cần re-login định kỳ
- Nếu admin revoke seat → phải `claude /login` lại
- **KHÔNG** set `ANTHROPIC_API_KEY` env var khi đã OAuth — sẽ override OAuth credential

### 3B. API key (BYOK — Bring Your Own Key)

Dùng khi:
- Cá nhân tự đăng ký, không thuộc team license
- Cần script CI/CD chạy headless (workflow GitHub Actions)
- Workspace personal Anthropic Console

```bash
# Cách 1: lệnh tương tác
claude /login
# chọn "API key" → paste key

# Cách 2: env var (cho headless / script)
export ANTHROPIC_API_KEY="sk-ant-..."
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc   # persist
```

Verify:

```bash
claude /status
# expected:
#   Auth: api_key
```

### 3C. So sánh nhanh

| Tiêu chí | OAuth Team | API key (BYOK) |
|---|---|---|
| Billing | Tập trung qua team | Cá nhân / project owner |
| Quota | Theo seat | Theo balance API |
| Quản lý seat | Admin console | Self-managed |
| Off-boarding khi dev nghỉ | Admin revoke seat | Phải rotate key thủ công |
| Dùng cho CI/GitHub Actions | ❌ Không (OAuth chỉ chạy interactive) | ✅ Có |
| Dùng cho local dev | ✅ Recommended | ✅ Vẫn được |
| Audit log (ai dùng cái gì) | ✅ Per-user trên console | ❌ Khó trace |

**Best practice cho team**:
- **Local dev**: dùng OAuth Team (3A)
- **CI/CD (GitHub Actions)**: dùng API key riêng (3B) lưu trong `secrets.ANTHROPIC_API_KEY` — tốt nhất là service-account key, không phải key cá nhân

---

## 4. Clone plugin vào repo backend

Có 2 cách. Khuyến nghị cách A (submodule) cho team — version-pin được.

### Cách A — Submodule (Recommended)

```bash
cd <your-backend-repo>
git submodule add https://github.com/huynq2207/everything-claude-code .claude/plugins/ecc
git submodule update --init --recursive
bash .claude/plugins/ecc/install.sh
```

### Cách B — Symlink global (cho cá nhân tự dùng)

```bash
git clone git@github.com:huynq2207/everything-claude-code.git ~/.claude/plugins/ecc
ln -sf ~/.claude/plugins/ecc/agents ~/.claude/agents
ln -sf ~/.claude/plugins/ecc/commands ~/.claude/commands
```

### Verify

```bash
ls .claude/agents/ | grep -E "code-reviewer|security-reviewer|planner"
# expected: code-reviewer.md, security-reviewer.md, planner.md
ls .claude/commands/ | grep -E "code-review|security-scan|plan"
# expected: code-review.md, security-scan.md, plan.md
```

---

## 5. Tuỳ biến cho project (1 lần)

Mở repo trong Claude Code:

```bash
cd <your-backend-repo>
claude
```

Trong session đầu tiên, chạy:

```
/init
```

Lệnh này tạo `CLAUDE.md` ở root repo. Sau đó edit để thêm context AI Agent Platform (tham khảo [agent-setup-guide.md](agent-setup-guide.md) section 3).

---

## 6. Workflow hằng ngày

### 6.1 Trước khi commit

```bash
# Trong Claude Code session
/code-review
```

Output: bảng finding HIGH/CRITICAL nếu có. Fix → review lại.

### 6.2 Trước khi push

```bash
/security-scan --min-severity medium
```

Có HIGH → fix tại chỗ:

```bash
/security-scan --fix    # auto-fix safe findings
```

### 6.3 Tạo PR

```bash
/pr
```

Tự sinh title + body theo template, push branch, mở PR.

### 6.4 Review PR đồng đội

```bash
# Trong terminal Claude Code
/code-review <PR_NUMBER>
```

Agent fetch PR, review, post comment.

---

## 7. Cheatsheet commands

| Lệnh | Khi dùng | Output |
|---|---|---|
| `/plan <feature>` | Đầu ticket | `plans/<ticket>/plan.md` |
| `/feature-dev` | Start ticket | guided workflow |
| `/code-review` | Trước push (local diff) | finding table |
| `/code-review <PR#>` | Review PR đồng đội | PR comment |
| `/security-scan` | Trước push | AgentShield report |
| `/security-scan --fix` | Khi có HIGH | auto-fix |
| `/pr` | Push xong | PR URL |
| `/learn` | Cuối sprint | rules extraction |
| `/build-fix` | Build/test fail | auto-fix |
| `/cost-report` | Weekly | token usage |

---

## 8. Pin model (khuyến nghị)

Edit frontmatter trong `.claude/agents/<agent>.md`:

```yaml
# code-reviewer.md, security-reviewer.md
model: sonnet         # balance cost/quality cho review hàng ngày

# planner.md, architect.md
model: opus           # cần reasoning sâu, chạy ít

# code-explorer.md
model: haiku          # read-only, ưu tiên speed
```

---

## 9. Tích hợp Git hooks (optional nhưng nên có)

Cài `husky` để auto-chạy security scan trước commit:

```bash
npm install -D husky
npx husky init
```

Edit `.husky/pre-commit`:

```bash
#!/usr/bin/env sh
. "$(dirname "$0")/_/husky.sh"

# Secret scan
npx gitleaks protect --staged --verbose || exit 1

# Quick AgentShield scan
npx ecc-agentshield scan --path . --min-severity high --staged-only || exit 1
```

Set executable:

```bash
chmod +x .husky/pre-commit
```

Bây giờ mỗi `git commit` sẽ chặn nếu có secret hoặc finding HIGH.

---

## 10. Troubleshooting

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `claude: command not found` | PATH chưa set | `export PATH="$HOME/.local/bin:$PATH"` |
| `Invalid API key` | Key sai/hết quota | `claude /login` lại; check console.anthropic.com |
| OAuth fail "no seat" | Admin chưa cấp seat | Liên hệ admin team workspace |
| OAuth bị API key override | Đang set `ANTHROPIC_API_KEY` env | `unset ANTHROPIC_API_KEY` rồi `claude /login` |
| Token expired | Hiếm — token tự refresh | `claude /logout && claude /login` |
| Agent không xuất hiện | `.claude/agents/` rỗng | Chạy lại `bash .claude/plugins/ecc/install.sh` |
| `/code-review` không thấy diff | Branch không có commit | `git status` check; commit trước |
| Hook husky không chạy | Chưa `chmod +x` | `chmod +x .husky/pre-commit` |
| Cost quá cao | Dùng opus cho mọi agent | Pin sonnet cho reviewer (xem section 8) |
| AgentShield false positive | Test fixture có fake secret | Thêm path vào `.gitleaks.toml` ignore list |
| Slow review | Repo lớn, không filter diff | Đảm bảo `git diff` chạy đúng phạm vi |

---

## 11. Verify checklist (chạy 1 lần sau khi setup)

```bash
# 1. CLI hoạt động
claude --version

# 2. Auth OK (OAuth team hoặc API key)
claude /status

# 3. Agents có mặt
ls .claude/agents/ | grep -E "code-reviewer|security-reviewer"

# 4. Commands có mặt
ls .claude/commands/ | grep -E "code-review|security-scan"

# 5. Test review trên 1 file
echo "console.log('test')" > /tmp/test.js
claude --print "/code-review /tmp/test.js"
```

Nếu cả 5 bước pass → ready to go.

---

## 12. Liên kết

- SDLC overall: [sdlc-overview.md](sdlc-overview.md)
- Project-level setup: [agent-setup-guide.md](agent-setup-guide.md)
- GitHub Actions auto-review: `.github/workflows/auto-code-review.yml`, `.github/workflows/auto-security-review.yml`
- Claude Code docs: <https://docs.claude.com/claude-code>
- AgentShield: <https://github.com/affaan-m/agentshield>

---

## Câu hỏi cần làm rõ

- Công ty đã có Claude Team / Enterprise plan chưa? Nếu có → ưu tiên OAuth (3A).
- Admin workspace là ai? Quy trình request seat?
- Team dùng zsh hay bash? (ảnh hưởng file `.zshrc`/`.bashrc` để persist env var khi dùng API key)
- CI/CD có nên dùng service-account API key tách biệt (không phải key cá nhân) không?
- Có cần Docker image dựng sẵn (chứa claude + agents) cho dev không quen setup không?
