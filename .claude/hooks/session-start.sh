#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Installs the dependencies needed so the dominant developer workflow in this
# monorepo — the Python packages under agent-governance-python/ — can be linted
# (ruff) and tested (pytest) inside a remote session.
#
# The Python install sequence mirrors the repo Dockerfile (the canonical
# "works together" set and ordering): the unpublished consolidated core
# packages are installed first with --no-deps so the legacy shim packages
# resolve without reaching PyPI for names that aren't published yet.
#
# Design notes:
#   * Synchronous (no async): guarantees deps are ready before the agent runs.
#   * Idempotent: pip editable installs are safe to re-run.
#   * Web-only: skips entirely outside Claude Code on the web.
#   * The native Agent Control Specification SDK build (maturin) and the OPA
#     CLI download are best-effort — a network hiccup there must not block
#     session startup. Core Python deps, ruff, and shared test deps are
#     required and will fail the hook if they don't install.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_DIR="$(pwd)"

PYROOT="agent-governance-python"

# The environment's system python3 is Debian-managed (its pip/setuptools/wheel
# and several deps cannot be uninstalled/upgraded in place), so install into a
# dedicated virtualenv instead of clobbering system site-packages. This matches
# the venv-based flow documented in CONTRIBUTING.md and keeps the session
# reproducible. .venv/ is already gitignored.
VENV="$PROJECT_DIR/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  echo "[session-start] Creating virtualenv at $VENV ..."
  python3 -m venv "$VENV"
fi
PY="$VENV/bin/python"

# Persist venv activation for the rest of the session (agent shells source this).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export VIRTUAL_ENV=\"$VENV\""
    echo "export PATH=\"$VENV/bin:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi
export VIRTUAL_ENV="$VENV"
export PATH="$VENV/bin:$PATH"

echo "[session-start] Upgrading pip toolchain (in venv)..."
$PY -m pip install --upgrade pip setuptools wheel

echo "[session-start] Installing unpublished consolidated core packages (--no-deps)..."
$PY -m pip install --no-deps \
  -e "$PYROOT/agent-governance-toolkit-core" \
  -e "$PYROOT/agent-governance-toolkit-integrations" \
  -e "$PYROOT/agent-governance-toolkit-cli" \
  -e "$PYROOT/agent-governance-toolkit-protocols"

echo "[session-start] Installing shared runtime deps + policy shim..."
$PY -m pip install "pydantic>=2.5.0,<3.0" "pyyaml>=6.0,<7.0"
$PY -m pip install --no-deps -e "$PYROOT/agt-policies"

echo "[session-start] Installing first-party Python packages (editable, with dev extras)..."
$PY -m pip install \
  "cedarpy>=4.0.0,<5.0" \
  -e "$PYROOT/agent-primitives[dev]" \
  -e "$PYROOT/agent-mcp-governance[dev]" \
  -e "$PYROOT/agent-os[full,dev]" \
  -e "$PYROOT/agent-mesh[agent-os,dev,server]" \
  -e "$PYROOT/agent-hypervisor[api,dev,nexus]" \
  -e "$PYROOT/agent-runtime" \
  -e "$PYROOT/agent-sre[api,dev]" \
  -e "$PYROOT/agent-compliance" \
  -e "$PYROOT/agent-marketplace[cli,dev]" \
  -e "$PYROOT/agent-lightning[agent-os,dev]"

DASHBOARD_REQS="$PYROOT/agent-hypervisor/examples/dashboard/requirements.txt"
if [ -f "$DASHBOARD_REQS" ]; then
  echo "[session-start] Installing hypervisor dashboard requirements..."
  $PY -m pip install -r "$DASHBOARD_REQS"
fi

echo "[session-start] Installing linter (ruff, CI-pinned) + shared test deps..."
# Match the ruff version CI lints with (agent-governance-python/requirements/ci-lint.txt).
$PY -m pip install "ruff==0.12.4"
CI_TEST_REQS="$PYROOT/requirements/ci-test.txt"
if [ -f "$CI_TEST_REQS" ]; then
  $PY -m pip install --require-hashes -r "$CI_TEST_REQS"
fi
$PY -m pip install "pytest-cov==7.1.0"

# --- Best-effort extras (must not block session startup) ---------------------

# Native Agent Control Specification SDK: agt-policies' v5 runtime bridge needs
# the compiled `agent_control_specification` binding for adapter checks. Built
# with maturin (Rust toolchain is provided by the environment).
echo "[session-start] (best-effort) Building native agent_control_specification SDK..."
if command -v cargo >/dev/null 2>&1; then
  if $PY -m pip install "maturin==1.8.7" \
     && $PY -m pip install --no-build-isolation ./policy-engine/sdk/python; then
    $PY -c "import agent_control_specification; print('agent_control_specification OK')" \
      || echo "[session-start] WARN: agent_control_specification import failed (some agent-os tests may skip)."
  else
    echo "[session-start] WARN: native SDK build failed; continuing without it."
  fi
else
  echo "[session-start] WARN: cargo not available; skipping native SDK build."
fi

# OPA CLI: required by OPAEvaluator local mode (opa eval subprocess) used by a
# subset of agent-os tests.
if ! command -v opa >/dev/null 2>&1; then
  echo "[session-start] (best-effort) Installing OPA CLI..."
  if curl --proto '=https' --tlsv1.2 -fSL \
       --retry 3 --retry-all-errors --retry-delay 3 --connect-timeout 20 \
       -o /tmp/opa \
       https://github.com/open-policy-agent/opa/releases/download/v1.4.2/opa_linux_amd64_static \
     && echo "2c0ccdbbe0b8e2a5d12d9c42d92f1f34f494ffb32d1f3c4ddc36101be637d66f  /tmp/opa" | sha256sum -c -; then
    chmod 755 /tmp/opa
    install -m 0755 /tmp/opa /usr/local/bin/opa 2>/dev/null \
      || { mkdir -p "$HOME/.local/bin" && install -m 0755 /tmp/opa "$HOME/.local/bin/opa" \
           && echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"; }
    rm -f /tmp/opa
  else
    echo "[session-start] WARN: OPA CLI download failed; OPA-dependent tests may skip."
  fi
fi

echo "[session-start] Done."
