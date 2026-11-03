#!/usr/bin/env bash
if [ -n "$DEBUG_SCRIPT" ] || [ -n "$GITPOD_HEADLESS" ]; then
    set -x
fi

# Since Drupal 11.4, the front controllers use the Symfony runtime.
patch=src/composer-drupal-core-setup/scaffold-patch-index-and-update-php.patch
if grep -q autoload_runtime web/index.php; then
    patch=src/composer-drupal-core-setup/scaffold-patch-index-and-update-php-runtime.patch
fi

git apply --directory=web -v "$patch"
