#!/bin/bash
# =============================================================================
# tests/test_browser_option.sh — QA for the ENABLE_BROWSER / --no-browser option
#
# Pure shell: no container runtime, no network (podman is stubbed). Run:
#   bash tests/test_browser_option.sh
#
# Covers: default unchanged (INSTALL_BROWSER=true, no tag suffix), --no-browser
# flag, ENABLE_BROWSER=false in versions.env, invalid value rejected,
# tag-suffix symmetry with up.sh/down.sh derivation, persistence of the
# effective flag back to versions.env, --browser force-true, and idempotent
# re-runs.
# =============================================================================
set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hs-test-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BIN="${WORK}/bin"; mkdir -p "$BIN"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want '$2' got '$3')"; }

# podman stub: record args, succeed
cat > "${BIN}/podman" <<'EOF'
#!/bin/bash
echo "PODMAN-ARGS: $*" >> "${CAPTURE_FILE:?}"
exit 0
EOF
chmod +x "${BIN}/podman"

# Fresh copy of the repo per scenario
fresh_repo() {
    rm -rf "${WORK}/repo"
    cp -r "${REPO_DIR}" "${WORK}/repo"
    rm -rf "${WORK}/repo/.git"
}
run_build() { ( cd "${WORK}/repo" && env PATH="${BIN}:$PATH" \
    CAPTURE_FILE="${WORK}/$1.args" ./build.sh "${@:2}" ) >"${WORK}/$1.out" 2>&1; }
tag_of() { grep -o -- '-t [^ ]*' "${WORK}/$1.args" 2>/dev/null | awk '{print $2}'; }

# Expected compound tag derived from versions.env — nothing hardcoded, so the
# suite survives version bumps without edits.
ver_clean() { sed 's/^v//' <<<"$1"; }
AGENT_PIN="$(grep -E '^AGENT_VERSION=' "${REPO_DIR}/versions.env" | cut -d= -f2)"
WEBUI_PIN="$(grep -E '^WEBUI_VERSION=' "${REPO_DIR}/versions.env" | cut -d= -f2)"
EXPECTED_TAG="$(ver_clean "$AGENT_PIN")-$(ver_clean "$WEBUI_PIN")"
OVERRIDE_AGENT="v2026.7.7.2"   # arbitrary older agent, test input only
OVERRIDE_TAG="$(ver_clean "$OVERRIDE_AGENT")-$(ver_clean "$WEBUI_PIN")-slim"

echo "== syntax =="
for f in build.sh up.sh down.sh; do
    bash -n "${REPO_DIR}/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
done

echo "== default: browser installed, tag unchanged =="
fresh_repo
run_build def
eq "exit code" "0" "$?"
eq "image tag has no suffix" "ascensionoid/hermes-suite:${EXPECTED_TAG}" "$(tag_of def)"
grep -q -- '--build-arg INSTALL_BROWSER=true' "${WORK}/def.args" && ok "INSTALL_BROWSER=true passed" || bad "INSTALL_BROWSER=true passed"

echo "== --no-browser flag: skipped, -slim suffix =="
fresh_repo
run_build nb --no-browser
eq "exit code" "0" "$?"
eq "image tag -slim suffix" "ascensionoid/hermes-suite:${EXPECTED_TAG}-slim" "$(tag_of nb)"
grep -q -- '--build-arg INSTALL_BROWSER=false' "${WORK}/nb.args" && ok "INSTALL_BROWSER=false passed" || bad "INSTALL_BROWSER=false passed"
grep -q 'Browser:        false' "${WORK}/nb.out" && ok "summary shows Browser: false" || bad "summary shows Browser: false"

echo "== ENABLE_BROWSER=false in versions.env (no flag) =="
fresh_repo
sed -i 's/^#ENABLE_BROWSER=false/ENABLE_BROWSER=false/' "${WORK}/repo/versions.env"
run_build envf
eq "exit code" "0" "$?"
eq "image tag -slim suffix" "ascensionoid/hermes-suite:${EXPECTED_TAG}-slim" "$(tag_of envf)"
grep -q -- '--build-arg INSTALL_BROWSER=false' "${WORK}/envf.args" && ok "INSTALL_BROWSER=false passed" || bad "INSTALL_BROWSER=false passed"

echo "== flag overrides versions.env (explicit true wins over file) =="
fresh_repo
sed -i 's/^#ENABLE_BROWSER=false/ENABLE_BROWSER=false/' "${WORK}/repo/versions.env"
# --browser force-true over a file false is covered in a later section.
# Here: file false + --agent override still slim:
run_build ov --agent v2026.7.7.2
eq "override keeps -slim" "ascensionoid/hermes-suite:${OVERRIDE_TAG}" "$(tag_of ov)"
grep -q -- '--build-arg AGENT_VERSION=v2026.7.7.2' "${WORK}/ov.args" && ok "agent override passed" || bad "agent override passed"

echo "== invalid ENABLE_BROWSER rejected =="
fresh_repo
sed -i 's/^#ENABLE_BROWSER=false/ENABLE_BROWSER=maybe/' "${WORK}/repo/versions.env"
run_build bad
[ "$?" != "0" ] && ok "nonzero exit on invalid value" || bad "nonzero exit on invalid value"
grep -q "ENABLE_BROWSER must be true or false" "${WORK}/bad.out" && ok "clear error message" || bad "clear error message"

echo "== docker-nolog: conf patched during build, restored after (stub docker) =="
# build.sh --docker-nolog seds supervisord.conf to /dev/null logging for the
# build, then restores it afterwards (git checkout, or sed fallback in
# non-git copies). Verify the round-trip and default build args with a
# stubbed docker binary — no docker daemon needed.
mkdir -p "${WORK}/home"
cat > "${BIN}/docker" <<'EOF'
#!/bin/bash
echo "DOCKER-ARGS: $*" >> "${CAPTURE_FILE:?}"
exit 0
EOF
chmod +x "${BIN}/docker"
fresh_repo
( cd "${WORK}/repo" && env HOME="${WORK}/home" PATH="${BIN}:$PATH" \
    CAPTURE_FILE="${WORK}/dn.args" ./build.sh --docker-nolog ) >"${WORK}/dn.out" 2>&1
eq "docker-nolog exit code" "0" "$?"
grep -q -- '--build-arg INSTALL_BROWSER=true' "${WORK}/dn.args" && ok "docker-nolog default INSTALL_BROWSER=true" || bad "docker-nolog default INSTALL_BROWSER=true"
grep -q 'Docker nolog mode' "${WORK}/dn.out" && ok "nolog mode announced" || bad "nolog mode announced"
grep -q 'stdout_logfile=/dev/null' "${WORK}/repo/supervisord.conf" && bad "conf restored after nolog build" || ok "conf restored after nolog build"
cmp -s "${REPO_DIR}/supervisord.conf" "${WORK}/repo/supervisord.conf" \
    && ok "supervisord.conf byte-identical to shipped" || bad "supervisord.conf byte-identical to shipped"

echo "== up.sh / down.sh derive matching tag (stub compose captures env) =="
# Hermetic HOME: up.sh/down.sh prepend $HOME/.local/bin to PATH (upstream
# design). With HOME pointed at an empty temp dir, a real podman-compose
# in the invoking user's ~/.local/bin can no longer override our stub.
cat > "${BIN}/podman-compose" <<'EOF'
#!/bin/bash
echo "COMPOSE-RUN: $*" >> "${CAPTURE_FILE:?}"
echo "TAG-IN-ENV: ${HERMES_SUITE_IMAGE_TAG:-unset}" >> "${CAPTURE_FILE:?}"
exit 0
EOF
chmod +x "${BIN}/podman-compose"
mkdir -p "${WORK}/home"
fresh_repo
sed -i 's/^#ENABLE_BROWSER=false/ENABLE_BROWSER=false/' "${WORK}/repo/versions.env"
( cd "${WORK}/repo" && env HOME="${WORK}/home" PATH="${BIN}:$PATH" CAPTURE_FILE="${WORK}/up.args" \
  bash up.sh ) >"${WORK}/up.out" 2>&1
eq "up.sh exit" "0" "$?"
grep -q "TAG-IN-ENV: ${EXPECTED_TAG}-slim" "${WORK}/up.args" && ok "up.sh exports slim tag for compose" || bad "up.sh exports slim tag for compose"
( cd "${WORK}/repo" && env HOME="${WORK}/home" PATH="${BIN}:$PATH" CAPTURE_FILE="${WORK}/down.args" \
  bash down.sh ) >"${WORK}/down.out" 2>&1
eq "down.sh exit" "0" "$?"
grep -q "TAG-IN-ENV: ${EXPECTED_TAG}-slim" "${WORK}/down.args" && ok "down.sh targets slim tag" || bad "down.sh targets slim tag"

echo "== up.sh / down.sh default tag unchanged (no ENABLE_BROWSER set) =="
fresh_repo
( cd "${WORK}/repo" && env HOME="${WORK}/home" PATH="${BIN}:$PATH" CAPTURE_FILE="${WORK}/updef.args" \
  bash up.sh ) >"${WORK}/updef.out" 2>&1
grep -q "TAG-IN-ENV: ${EXPECTED_TAG}" "${WORK}/updef.args" && ! grep -q "slim" "${WORK}/updef.args" \
    && ok "default up.sh tag has no suffix" || bad "default up.sh tag has no suffix"

echo "== persistence: --no-browser flag written back to versions.env =="
fresh_repo
run_build pers --no-browser
eq "exit code" "0" "$?"
grep -q '^ENABLE_BROWSER=false' "${WORK}/repo/versions.env" && ok "versions.env records ENABLE_BROWSER=false" || bad "versions.env records ENABLE_BROWSER=false"
grep -q 'Browser setting persisted' "${WORK}/pers.out" && ok "persistence announced" || bad "persistence announced"
mkdir -p "${WORK}/home"
( cd "${WORK}/repo" && env HOME="${WORK}/home" PATH="${BIN}:$PATH" CAPTURE_FILE="${WORK}/persup.args" \
  bash up.sh ) >"${WORK}/persup.out" 2>&1
grep -q "TAG-IN-ENV: ${EXPECTED_TAG}-slim" "${WORK}/persup.args" && ok "up.sh derives slim after persisted flag" || bad "up.sh derives slim after persisted flag"

echo "== persistence: default build leaves versions.env untouched =="
fresh_repo
run_build ptouch
eq "exit code" "0" "$?"
grep -qE '^ENABLE_BROWSER=' "${WORK}/repo/versions.env" && bad "default build must not write ENABLE_BROWSER" || ok "default build must not write ENABLE_BROWSER"
grep -q '^#ENABLE_BROWSER=false' "${WORK}/repo/versions.env" && ok "commented example preserved as comment" || bad "commented example preserved as comment"

echo "== --browser flag overrides file false and flips it back =="
fresh_repo
sed -i 's/^#ENABLE_BROWSER=false/ENABLE_BROWSER=false/' "${WORK}/repo/versions.env"
run_build fb --browser
eq "exit code" "0" "$?"
eq "--browser over file-false: full tag, no suffix" "ascensionoid/hermes-suite:${EXPECTED_TAG}" "$(tag_of fb)"
grep -q -- '--build-arg INSTALL_BROWSER=true' "${WORK}/fb.args" && ok "INSTALL_BROWSER=true passed" || bad "INSTALL_BROWSER=true passed"
grep -q '^ENABLE_BROWSER=true' "${WORK}/repo/versions.env" && ok "file flipped back to true" || bad "file flipped back to true"

echo "== persistence is idempotent (no duplicate lines) =="
fresh_repo
run_build idem --no-browser
run_build idem2 --no-browser
eq "exactly one ENABLE_BROWSER line after re-run" "1" "$(grep -c '^ENABLE_BROWSER=' "${WORK}/repo/versions.env")"

echo ""
echo "=========================================="
echo " Passed: $PASS   Failed: $FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ]
