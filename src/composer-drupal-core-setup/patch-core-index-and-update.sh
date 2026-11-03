#!/usr/bin/env bash
if [ -n "$DEBUG_SCRIPT" ] || [ -n "$GITPOD_HEADLESS" ]; then
    set -x
fi

patch_file=src/composer-drupal-core-setup/scaffold-patch-index-and-update-php.patch
if grep -Fq "require_once 'autoload_runtime.php';" web/index.php; then
    patch_file=src/composer-drupal-core-setup/scaffold-patch-runtime-index-and-update-php.patch
fi

if git apply --directory=web --reverse --check "$patch_file" 2>/dev/null; then
    exit 0
fi

git apply --directory=web -v "$patch_file"
