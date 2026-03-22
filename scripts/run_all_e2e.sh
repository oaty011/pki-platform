#!/usr/bin/env bash
set -euo pipefail

SCRIPTS=(
  "scripts/verify_app_e2e_happy_path.sh"
  "scripts/verify_ecu_e2e_happy_path.sh"
  "scripts/verify_app_subject_mismatch.sh"
  "scripts/verify_ecu_subject_mismatch.sh"
)

for script in "${SCRIPTS[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "[FAIL] missing script: $script" >&2
    exit 1
  fi

  echo
  echo "=================================================="
  echo "== RUNNING: $script"
  echo "=================================================="
  bash "$script"
  echo "=================================================="
  echo "== PASSED: $script"
  echo "=================================================="
done

echo
echo "[PASS] all E2E checks passed"
