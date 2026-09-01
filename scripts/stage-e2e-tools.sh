#!/bin/sh
# shellcheck disable=SC2029

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_GUEST_ROOT="jfc-e2e/repo/E2E"

ssh "$JFC_VM_HOST" \
  "/bin/mkdir -p '$JFC_GUEST_ROOT/InstallJFC' '$JFC_GUEST_ROOT/ScenarioExecutor' '$JFC_GUEST_ROOT/VM'"
scp \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/accessibility-permission.mjs" \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/agent-lifecycle.mjs" \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/complete-authorization.jxa" \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/onboarding.mjs" \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/reset-product-state.sh" \
  "$JFC_REPOSITORY_ROOT/E2E/InstallJFC/start-at-login.mjs" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/InstallJFC/"
scp \
  "$JFC_REPOSITORY_ROOT/E2E/ScenarioExecutor/appium.mjs" \
  "$JFC_REPOSITORY_ROOT/E2E/ScenarioExecutor/pointer.swift" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/ScenarioExecutor/"
scp \
  "$JFC_REPOSITORY_ROOT/E2E/VM/start-appium.sh" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/VM/"
ssh "$JFC_VM_HOST" "/bin/chmod 0755 '$JFC_GUEST_ROOT/VM/start-appium.sh'"
ssh "$JFC_VM_HOST" \
  "/bin/chmod 0755 '$JFC_GUEST_ROOT/InstallJFC/reset-product-state.sh'"

echo "staged E2E beforeAll tools on $JFC_VM_HOST"
