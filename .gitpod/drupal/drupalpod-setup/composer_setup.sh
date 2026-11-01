#!/usr/bin/env bash
set -eu -o pipefail

# For versions end with x - add `-dev` suffix (ie. 9.3.x-dev)
# For versions without x - add `~` prefix (ie. ~9.2.0)
d="$DP_CORE_VERSION"
case $d in
*.x)
    install_version="$d"-dev
    ;;
*)
    install_version=~"$d"
    ;;
esac

# Create required composer.json and composer.lock files
cd "$GITPOD_REPO_ROOT" && time ddev . composer create -n --no-install drupal/recommended-project:"$install_version" temp-composer-files
rm "$GITPOD_REPO_ROOT"/temp-composer-files/composer.lock
cp "$GITPOD_REPO_ROOT"/temp-composer-files/* "$GITPOD_REPO_ROOT"/.
rm -rf "$GITPOD_REPO_ROOT"/temp-composer-files

# Programmatically fix Composer 2.2 allow-plugins to avoid errors
ddev composer config --no-plugins allow-plugins.composer/installers true
ddev composer config --no-plugins allow-plugins.drupal/core-project-message true
ddev composer config --no-plugins allow-plugins.drupal/core-vendor-hardening true
ddev composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true

ddev composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
ddev composer config --no-plugins allow-plugins.phpstan/extension-installer true

ddev composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true

ddev composer config --no-plugins allow-plugins.php-http/discovery true

ddev composer config --no-plugins allow-plugins.tbachert/spi true

# packages.drupal.org adds "drupal/toolbar": "*" to admin_toolbar. Drupal core
# only declares that it replaces drupal/toolbar since 10.6.15/11.3.20/11.4.5;
# otherwise Composer falls back to the contrib Toolbar project (Drupal 11.3+).
# Provide it from the root project; unlike replace, this doesn't conflict with
# newer core releases. `composer config` can't set "provide", so use jq.
if [ "$DP_EXTRA_ADMIN_TOOLBAR" == '1' ] && [[ "$DP_CORE_VERSION" =~ ^10(\..*)?$ ]]; then
    cd "$GITPOD_REPO_ROOT" &&
        echo "$(jq '.provide["drupal/toolbar"] = "*"' composer.json --indent 4)" >composer.json
fi

# Add project source code as symlink (to repos/name_of_project)
# double quotes explained - https://stackoverflow.com/a/1250279/5754049
if [ -n "$DP_PROJECT_NAME" ]; then
    cd "${GITPOD_REPO_ROOT}" &&
        ddev composer config \
            repositories.core1 \
            '{"type": "path", "url": "repos/'"$DP_PROJECT_NAME"'", "options": {"symlink": true}}'

    cd "$GITPOD_REPO_ROOT" &&
        ddev composer config minimum-stability dev
fi
