# SDLC Overview — AI Agent Platform (Backend Team)

> Quy trình phát triển phần mềm cho team xây dựng nền tảng AI Agent kết nối dữ liệu nội bộ công ty.
> **Mục tiêu**: vận hành ổn định, phân quyền chặt, có monitor & scale.

---

## 1. Nguyên tắc cốt lõi

1. **Threat-model trước, code sau** — bất kỳ feature nào chạm tới: auth, MCP server, prompt, tool/connector, audit log → phải có ADR + threat-model duyệt trước.
2. **2 lớp review trên mọi PR** — `code-reviewer` (chất lượng) + `security-reviewer` (an toàn). Không bypass.
3. **TDD diff coverage ≥ 80%** — đo trên dòng code mới, không đo tổng repo.
4. **Audit log là first-class** — mọi agent-call, tool-call, data-access đều log (who, what, when, scope, result).
5. **Canary trước, full rollout sau** — 5% → 25% → 100%, có rollback button.

---

## 2. 7 bước SDLC

```
┌──────────────────────────────────────────────────────────────────┐
│  INTAKE → DESIGN → BUILD → REVIEW → TEST → RELEASE → OBSERVE    │
└──────────────────────────────────────────────────────────────────┘
```

### Bước 1. Intake & PRD

- **Input**: yêu cầu từ PM/stakeholder
- **Output**: `prds/<feature>.prd.md` chứa: scope, data sources truy cập, permission model, SLA, success metrics
- **Owner**: PM + Tech Lead
- **Lệnh**: `/plan-prd`

### Bước 2. Design

- **Input**: PRD
- **Output**:
  - ADR trong `docs/architecture/adr-<NNN>-<slug>.md`
  - Threat-model section trong ADR (STRIDE)
  - Plan phases: `plans/<ticket>/plan.md` + `phase-XX-*.md`
- **Owner**: Tech Lead
- **Lệnh**: `/plan <ticket>`
- **Agent**: `planner` (opus), `architect`

### Bước 3. Build (TDD)

- **Input**: phase file
- **Output**: code + tests trên branch `feat/<ticket>-<slug>`
- **Owner**: Dev
- **Lệnh**: `/feature-dev`
- **Agent**: `tdd-guide`, `code-architect`
- **Commit convention**: `feat(<scope>): ...`, `fix(<scope>): ...`, `test(<scope>): ...`

### Bước 4. Self-review

- **Input**: local diff trước khi push
- **Output**: clean diff, lint pass, type pass, tests xanh
- **Owner**: Dev
- **Lệnh**: `/code-review` (local mode)

### Bước 5. PR Review

- **Input**: PR mở từ feat → staging
- **Output**: 2 reviewer approved (1 peer + 1 security gate)
- **Owner**: Tech Lead + 1 Senior peer
- **Lệnh**: `/code-review <PR#>`, `/security-scan --min-severity medium`
- **Agent**: `code-reviewer` + `security-reviewer` chạy đồng thời

> **Gate cứng**: nếu `security-reviewer` raise finding ≥ HIGH → không merge cho tới khi fix + scan lại clean.

### Bước 6. Release

- **Input**: PR merged vào staging → main
- **Output**: deploy canary với feature flag
- **Owner**: Tech Lead + SRE
- **Quy trình**:
  1. Merge `staging → main`
  2. CI build image
  3. Deploy canary 5% (15 phút quan sát)
  4. 25% (30 phút)
  5. 100%
  6. Tag release `v<MAJOR>.<MINOR>.<PATCH>`
- **Rollback**: 1 command, < 2 phút

### Bước 7. Observe

- **Output**:
  - Dashboard: latency p50/p95/p99, error rate, token cost, per-agent call volume
  - Alert: error rate spike, cost spike, permission-denied spike
  - Audit log search UI
  - On-call rota (PagerDuty/Opsgenie)
- **Owner**: SRE + Tech Lead
- **Weekly retro**: dùng `/learn` extract pattern → đẩy vào `rules/` để agent tự áp dụng lần sau

---

## 3. Definition of Done (DoD)

Một ticket được coi là DONE khi đủ 5 mục:

- [ ] Test diff coverage ≥ 80%
- [ ] `/security-scan` clean ở mức `--min-severity medium`
- [ ] ADR cập nhật nếu đổi boundary (data source mới, role mới, MCP server mới)
- [ ] Audit log + metric tag cho mọi endpoint/tool mới
- [ ] Runbook trong `docs/runbooks/<feature>.md` (rollback + on-call playbook)

---

## 4. Branching & Versioning

| Branch | Mục đích | Protection |
|---|---|---|
| `main` | Production | Required: 2 review, CI green, security-gate pass |
| `staging` | Pre-prod, soak 24h | Required: 1 review, CI green |
| `feat/<ticket>-<slug>` | Feature work | Tự do |
| `hotfix/<slug>` | Critical prod fix | Direct → main, post-mortem bắt buộc |

**Versioning**: SemVer. `MAJOR` cho breaking change agent API, `MINOR` cho feature mới, `PATCH` cho bug fix.

---

## 5. Quality Gates (CI/CD)

| Gate | Tool | Block merge? |
|---|---|---|
| Lint | `eslint`, `markdownlint` | Yes |
| Type check | `tsc`, `mypy` | Yes |
| Unit + integration test | `node tests/run-all.js` / pytest | Yes |
| Diff coverage ≥ 80% | `c8` / coverage.py | Yes |
| Security scan (HIGH+) | AgentShield (`/security-scan`) | Yes |
| Secret scan | `gitleaks` | Yes |
| Dependency audit | `npm audit --audit-level=high` | Yes |
| E2E smoke | `e2e-runner` agent | Yes (cho release tới main) |

---

## 6. Quy ước cho code chạm "khu vực nhạy cảm"

Path kích hoạt review tăng cường (security-reviewer bắt buộc + Tech Lead approve):

- `src/auth/**` — authentication, RBAC, session
- `src/mcp/**` — MCP server, tool registration, prompt template
- `src/connectors/**` — data source connector (DB, file, third-party API)
- `src/prompts/**` — prompt template (rủi ro prompt injection)
- `src/audit/**` — audit log pipeline
- `config/permissions/**` — permission policy

---

## 7. Incident Response (tóm tắt)

1. **Detect** — alert hoặc user report
2. **Triage** — phân loại Sev1/2/3 (Sev1 = data leak / auth bypass)
3. **Mitigate** — rollback hoặc feature flag off trong < 5 phút (Sev1)
4. **Communicate** — báo trong `#incident` channel, status page
5. **Root cause** — post-mortem trong 48h, lưu `docs/postmortems/<date>-<slug>.md`
6. **Action items** — gắn ticket trong sprint kế tiếp

---

## 8. Cadence

| Hoạt động | Tần suất |
|---|---|
| Stand-up | Daily, 15 phút |
| Sprint planning | 2 tuần/lần |
| Architecture review | Weekly, Tech Lead chủ trì |
| Security retro | Monthly |
| `/learn` extract pattern → `rules/` | Cuối mỗi sprint |
| Postmortem review | Sau mỗi Sev1/Sev2 |

---

## 9. Tham khảo

- Setup agent: [agent-setup-guide.md](agent-setup-guide.md)
- Plugin nguồn: [everything-claude-code](https://github.com/cnnct/everything-claude-code)
- AgentShield: <https://github.com/affaan-m/agentshield>

---

## Câu hỏi cần làm rõ

- Stack chính của team là gì (Node/NestJS, Python/FastAPI, Go)? → chọn skill pattern cụ thể.
- CI hiện tại đã có GitHub Actions chưa? → wire AgentShield phù hợp.
- On-call tooling đang dùng PagerDuty hay Opsgenie?
- Có sẵn audit log pipeline (Elastic/ClickHouse/BigQuery)?
