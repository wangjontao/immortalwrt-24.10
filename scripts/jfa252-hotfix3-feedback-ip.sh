#!/bin/sh
# Offline installer source is packaged together with the ARM64 fastacl252-probe binary.
# The live bundle distributed from ChatGPT applies these same source patches:
# - stale /tmp/fastacl252-edit.lock recovery (120 s TTL)
# - fastacl252_probe LuCI endpoint
# - save/apply wait + configuration read-back verification
# - per-node/device/WiFi exit-IP UI feedback
#
# Build the companion ARM64 binary with .github/workflows/FastACL252-probe-hotfix.yml.
set -eu

echo "Use the offline JuLiangTK-FastACL252-HOTFIX3-feedback-ip bundle containing:"
echo "  jfa252-hotfix3.sh"
echo "  fastacl252-probe"
echo "The router-side installer intentionally performs no network download."
