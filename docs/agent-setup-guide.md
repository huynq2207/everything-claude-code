# Agent Setup Guide — Tech Lead Productivity

> Hướng dẫn cài & vận hành các agent chuyên biệt cho Tech Lead role trên dự án **AI Agent Platform**.
> Mục tiêu: Tech Lead **không review code thô** — agent chạy trước, lead chỉ duyệt finding HIGH/CRITICAL.

---

## 1. Tổng quan agents dùng cho Tech Lead

| Agent | Vai trò | Model | Khi dùng |
|---|---|---|---|
| `planner` | Lập kế hoạch & break-down feature | `opus` | Đầu mỗi ticket lớn |
| `architect` | Thiết kế hệ thống, chọn pattern | `opus` | Khi cần ADR |
| `code-reviewer` | Review chất lượng code | `sonnet` | Mọi PR |
| `security-reviewer` | Phát hiện OWASP + prompt-injection + secret | `sonnet` | Mọi PR chạm khu vực nhạy cảm |
| `tdd-guide` | Hướng dẫn dev viết test trước | `sonnet` | Dev start ticket |
| `e2e-runner` | Chạy & phân tích E2E test | `sonnet` | Trước release |
| `code-explorer` | Trace luồng code | `sonnet` | Khi onboarding code mới |

---

## 2. Cài đặt plugin vào repo backend

### Bước 1. Clone plugin

```bash
# Tại repo backend của team
cd <your-repo>
git submodule add https://github.com/<org>/everything-claude-code .claude/plugins/ecc
```

### Bước 2. Chạy installer

```bash
bash .claude/plugins/ecc/install.sh
```

Kết quả: `agents/`, `commands/`, `hooks/hooks.json`, `rules/` được sym-link vào `.claude/`.

### Bước 3. Verify

```bash
ls .claude/agents/   # phải thấy code-reviewer.md, security-reviewer.md, planner.md
ls .claude/commands/ # phải thấy code-review.md, security-scan.md, plan.md, pr.md
```

---

## 3. Tùy biến agent cho context AI Agent Platform

### 3.1 `security-reviewer.md`

Mở file `.claude/agents/security-reviewer.md`, thêm vào section "When to Run":

```yaml
# Trigger paths (project-specific cho AI Agent Platform)
ALWAYS_TRIGGER_ON:
  - src/auth/**          # authentication, RBAC, session
  - src/mcp/**           # MCP server, tool registration
  - src/connectors/**    # data source connectors
  - src/prompts/**       # prompt templates (prompt-injection risk)
  - src/audit/**         # audit log pipeline
  - config/permissions/**
  - env var changes
  - new role / new scope / new tool exposure
```

Thêm checklist riêng cho AI Agent context (cuối file):

```markdown
## AI Agent Platform — Extra Checks

### Prompt Injection
- [ ] User input có được phân tách rõ khỏi system prompt?
- [ ] Có sanitize URL/file path trước khi cho LLM dùng tool?
- [ ] Tool call có whitelist params, không allow free-form shell?

### Data Boundary
- [ ] Mọi query DB có RBAC check theo user/role hiện tại?
- [ ] Output của agent có redact PII trước khi trả về?
- [ ] Audit log có ghi: actor, tool, input hash, output hash, timestamp?

### MCP Server
- [ ] Tool descriptions không chứa instruction "ignore previous"?
- [ ] Tool input schema strict, không allow `Any` / `object`?
- [ ] MCP transport có TLS + auth header?

### Rate Limit & Cost
- [ ] Mỗi user/role có quota tokens/day?
- [ ] Có circuit breaker khi LLM cost spike?
```

### 3.2 `code-reviewer.md`

Giữ nguyên "Pre-Report Gate" + "Confidence Filtering" (đã có sẵn — quan trọng để tránh review noise). Chỉ thêm vào section "Common False Positives - Skip These":

```markdown
- "Missing await" trên `auditLog.emit(...)` — đây là fire-and-forget có chủ đích.
- "Should use enum" cho tool name string — vì tool registry là dynamic.
```

### 3.3 `planner.md`

Thêm template cho AI Agent Platform vào cuối file:

```markdown
## AI Agent Feature Plan Template

Khi planning feature có chạm AI Agent flow, plan PHẢI có:

1. **Permission model**: ai được dùng, scope nào
2. **Data access**: source nào, RBAC check ở đâu
3. **Audit events**: log những gì
4. **Failure modes**: LLM timeout, tool error, permission deny
5. **Cost estimate**: tokens/call × calls/day
6. **Rollback plan**: feature flag name + thời gian rollback
```

---

## 4. Hooks — tự động hoá

File `.claude/hooks/hooks.json`:

### 4.1 Cảnh báo khi edit khu vực nhạy cảm

```jsonc
{
  "PreToolUse": [
    {
      "matcher": "Edit|Write",
      "paths": [
        "src/auth/**",
        "src/mcp/**",
        "src/connectors/**",
        "src/prompts/**",
        "src/audit/**"
      ],
      "command": "node .claude/plugins/ecc/scripts/hooks/notify-security-review.js",
      "async": true,
      "timeout": 5
    }
  ]
}
```

Tác dụng: khi dev sửa file nhạy cảm → hook in cảnh báo "Nhớ chạy `/security-scan` trước khi push".

### 4.2 Chặn push nếu test fail

```jsonc
{
  "Stop": [
    {
      "command": "node .claude/plugins/ecc/scripts/hooks/run-tests-and-lint.js",
      "async": false,
      "timeout": 120
    }
  ]
}
```

Tác dụng: Claude Code session kết thúc sẽ chạy `npm test` + `npm run lint`. Fail = thông báo cho dev.

### 4.3 Auto secret scan trước commit

Hooks Git (không phải Claude hooks) — thêm vào `.husky/pre-commit`:

```bash
#!/usr/bin/env sh
. "$(dirname "$0")/_/husky.sh"

npx gitleaks protect --staged --verbose
npx ecc-agentshield scan --path . --min-severity high --format text
```

---

## 5. Commands hằng ngày cho Tech Lead

### 5.1 Workflow chuẩn 1 ngày

```bash
# Morning — review backlog
/plan                  # check ticket pool, prioritize

# Mỗi PR review
/code-review <PR#>          # logic & quality
/security-scan --min-severity medium  # security

# Trước khi release
/security-scan --min-severity high
gh pr merge <PR#> --squash

# End of sprint
/learn                 # extract pattern từ session
```

### 5.2 Cheatsheet

| Lệnh | Mục đích | Thời gian |
|---|---|---|
| `/plan <feature>` | Tạo plan + phases | 5–10' |
| `/feature-dev` | Dev start ticket | tự chạy |
| `/code-review` (local) | Self-review trước push | 1–2' |
| `/code-review <PR#>` | Review PR trên GitHub | 3–5' |
| `/security-scan` | AgentShield scan | 2' |
| `/security-scan --fix` | Auto-fix safe finding | 3' |
| `/pr` | Tạo PR có template | 30s |
| `/learn` | Extract pattern → rules | 5' |
| `/build-fix` | Fix build error | 2–5' |
| `/cost-report` | Token cost report | 1' |

---

## 6. CI/CD wiring (GitHub Actions)

### 6.1 Security gate

`.github/workflows/security-gate.yml`:

```yaml
name: Security Gate
on:
  pull_request:
    branches: [main, staging]

jobs:
  agentshield:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: affaan-m/agentshield@v1
        with:
          path: "."
          min-severity: "high"
          fail-on-findings: true

  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  dependency-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm audit --audit-level=high
```

### 6.2 Code review bot (optional)

`.github/workflows/auto-review.yml` — gọi Claude qua GitHub Action khi PR mở:

```yaml
name: Auto Code Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          api-key: ${{ secrets.ANTHROPIC_API_KEY }}
          command: "/code-review --pr ${{ github.event.pull_request.number }}"
```

Bot sẽ post comment review vào PR. Tech Lead chỉ cần check finding HIGH+.

---

## 7. Productivity tips

### 7.1 Chạy 2 review song song

Trong 1 PR, mở 2 session Claude Code:
- **Session A**: `/code-review <PR#>` — chất lượng
- **Session B**: `/security-scan` — an toàn

Tiết kiệm ~50% thời gian so với chạy tuần tự.

### 7.2 Pin model cho từng agent

`.claude/agents/<agent>.md` frontmatter:

| Agent | Model | Lý do |
|---|---|---|
| `planner` | `opus` | Chạy 1 lần/ticket, cần reasoning sâu |
| `architect` | `opus` | Cần reasoning sâu cho ADR |
| `code-reviewer` | `sonnet` | Chạy nhiều, balance cost/quality |
| `security-reviewer` | `sonnet` | Chạy nhiều, pattern-based đủ tốt |
| `tdd-guide` | `sonnet` | Dev dùng hàng ngày |
| `code-explorer` | `haiku` | Read-only, cần nhanh |

### 7.3 Đừng review code thô

Quy trình review PR đúng:

1. Đọc bảng finding của `code-reviewer` (~30s)
2. Đọc bảng finding của `security-reviewer` (~30s)
3. Chỉ open file khi có finding HIGH/CRITICAL hoặc khi không hiểu intent
4. Comment trực tiếp trên finding (không cần re-explain)
5. Approve hoặc request changes

Nếu cả 2 agent return zero finding → approve thẳng, không cần đọc diff.

### 7.4 Weekly `/learn`

Cuối mỗi sprint, chạy `/learn` để extract pattern recurring từ session:

- Pattern review trùng → đưa vào `rules/`
- Pattern bug trùng → đưa vào `agents/<lang>-reviewer.md` checklist
- Pattern command trùng → tạo command mới

Tích luỹ qua thời gian, agent sẽ tự bắt được lỗi mà không cần Tech Lead nhắc.

---

## 8. Troubleshooting

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| Agent không trigger | Frontmatter thiếu | Check `tools:` + `model:` field |
| Hook không chạy | Path không match | Verify glob trong `hooks.json` |
| Security scan false positive nhiều | Test fixture chứa fake secret | Add path vào `.gitleaks.toml` ignore |
| `code-reviewer` flood finding LOW | Confidence filter tắt | Đảm bảo "Pre-Report Gate" trong agent file |
| Plan output quá dài | Không break thành phase | Force `planner` sinh phase files |

---

## 9. Liên kết

- SDLC: [sdlc-overview.md](sdlc-overview.md)
- Plugin source: `.claude/plugins/ecc/`
- Hook scripts: `.claude/plugins/ecc/scripts/hooks/`
- AgentShield docs: <https://github.com/affaan-m/agentshield>

---

## Câu hỏi cần làm rõ

- Team đã có `husky` cho git hooks chưa? Nếu chưa cần cài thêm.
- ANTHROPIC_API_KEY cấp quota bao nhiêu? Ảnh hưởng tới việc dùng `opus` cho `planner`.
- Có cần plugin Slack notify khi security-gate fail không?
- Audit log pipeline có sẵn API ingest hay phải dev mới?
