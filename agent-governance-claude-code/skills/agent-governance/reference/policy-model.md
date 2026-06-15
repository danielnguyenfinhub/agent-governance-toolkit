# AGT Claude Code policy model

Reference for the policy consumed by the `agt-governance` plugin. The bundled default
lives at `config/default-policy.json`; this document explains its shape so you can read
`agt_policy_status` output and explain decisions.

## Top-level fields

| Field | Meaning |
|-------|---------|
| `mode` | `enforce` applies effects; other modes may observe only. |
| `denyOnPolicyError` | When `true`, any evaluation error resolves to `deny` (fail closed). |
| `minimumPromptDefenseGrade` | Lowest acceptable prompt-defense grade (e.g. `B`) before a prompt is blocked. |
| `toolPolicies` | Allow / block / review lists and the default effect for tools. |
| `blockedToolCalls` | Command-pattern rules, primarily against `Bash`. |
| `directResourcePolicies` | Path and URL rules for direct resource access. |
| `poisoningPatterns` | Regexes flagged as prompt-injection / poisoning, with severity. |
| `additionalContext` | Governance reminders injected at session start. |

## Decisions are tri-state

Every evaluation returns `allow`, `deny`, or `review`:

- **allow** — listed in `toolPolicies.allowedTools`.
- **deny** — matches a `deny` rule, or an error occurred under `denyOnPolicyError`.
- **review** — listed in `reviewTools`, matches a `review` rule, or hits `defaultEffect`.

`defaultEffect` in the bundled policy is `review`, so an unrecognized tool is **not**
auto-allowed.

## `toolPolicies` (default)

- `allowedTools`: `Read`, `Glob`, `Grep`, and the two AGT MCP tools.
- `reviewTools`: `Bash`, `WebFetch`, `WebSearch`, `Write`, `Edit`, `MultiEdit`.
- `blockedTools`: empty by default.
- `defaultEffect`: `review`.

## `blockedToolCalls` (default rules)

Each rule has an `id`, target `tool`, `effect`, human-readable `reason`, and
`commandPatterns` (regex `source` + `flags`).

- `recursive-delete` — `deny` — `rm -rf` outside common build artifacts.
- `dangerous-bootstrap` — `deny` — `curl|wget … | sh/bash`, `bash <(curl|wget …)`,
  and cloud metadata endpoints.
- `secret-read` — `deny` — reading `.env`, `id_rsa`/`id_ed25519`, `~/.ssh`, `~/.aws`,
  `~/.azure`, gcloud/gh/docker/kube config, `.netrc`, `.git-credentials`, `.npmrc`,
  `.pypirc`, `secrets.json`, and environment dumps (`printenv`, `env`, `Get-ChildItem Env:`).

## `directResourcePolicies`

**`pathRules`**
- `credential-read-paths` — `deny` reads of credential/secret paths; `.env.example`,
  `.env.sample`, `.env.template` are explicitly allowed via `allowPathPatterns`.
- `persistence-write-paths` — `review` writes to `.bashrc`, `.zshrc`, `.profile`,
  `.gitconfig`, `package.json`, `.ssh/config`, `.vscode/tasks.json`, `.git/hooks/`.

**`urlRules`**
- `metadata-endpoints` — `deny` access to `169.254.169.254`, `100.100.100.200`,
  `metadata.google.internal`.

## `poisoningPatterns` (default)

- `ignore previous instructions` — `critical` — direct prompt injection.
- `reveal (the )?(system|developer) prompt` — `critical` — hidden-instruction exfiltration.

## Composition

In the broader toolkit, policies compose Org → Team → Agent, and the **stricter** effect
always wins. Within Claude Code the plugin loads a single resolved policy (see loading
order in `SKILL.md`); treat any locally-overridden policy as authoritative for the session
while keeping the deny-by-default and fail-closed guarantees.
