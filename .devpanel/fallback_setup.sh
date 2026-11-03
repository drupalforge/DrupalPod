#!/usr/bin/env bash
set -eu -o pipefail

# Set a default setup (when project type is not specified)
export DP_INSTALL_PROFILE='demo_umami'
export DP_PROJECT_TYPE='project_core'
export DP_PROJECT_NAME="drupal"
if [ -z "${DP_CORE_VERSION:-}" ]; then
    # Use the latest stable Drupal core release that supports this PHP version.
    tmp=$(mktemp -d)
    echo '{"require":{"drupal/core":"*"}}' > "$tmp/composer.json"
    status=0
    composer -d "$tmp" update --no-install --no-plugins --no-scripts --no-progress -q || status=$?
    case $status in
    0)
        DP_CORE_VERSION=$(php -r 'foreach (json_decode(file_get_contents($argv[1]))->packages as $p) if ($p->name === "drupal/core") echo $p->version;' "$tmp/composer.lock")
        ;;
    2)
        # Composer found no Drupal core release compatible with this PHP version.
        DP_CORE_VERSION=
        ;;
    *)
        if php -r 'exit(PHP_VERSION_ID >= 80300 ? 0 : 1);'; then
            DP_CORE_VERSION=11.4.11
        else
            DP_CORE_VERSION=10.6.20
        fi
        echo "Could not determine the latest Drupal core release; using $DP_CORE_VERSION." >&2
        ;;
    esac
    rm -rf "$tmp"
    if [ -z "$DP_CORE_VERSION" ]; then
        echo "No Drupal core release is compatible with PHP $(php -r 'echo PHP_VERSION;')." >&2
        exit 1
    fi
fi
export DP_CORE_VERSION
export DP_EXTRA_DEVEL=1
export DP_EXTRA_ADMIN_TOOLBAR=1
