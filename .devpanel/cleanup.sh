#!/usr/bin/env bash
set -eu -o pipefail

# Remove composer.json and composer.lock. Fresh ones will be generated.
rm -f "${APP_ROOT}"/composer.json "${APP_ROOT}"/composer.lock
