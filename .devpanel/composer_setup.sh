#!/usr/bin/env bash
set -eu -o pipefail
cd $APP_ROOT

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

if [ ! -f composer.json ]; then
    # Create required composer.json and composer.lock files
    time composer create-project -n --no-install drupal/recommended-project:"$install_version" temp-composer-files
    rm "$APP_ROOT"/temp-composer-files/composer.lock
    cp "$APP_ROOT"/temp-composer-files/* "$APP_ROOT"/.
    rm -rf "$APP_ROOT"/temp-composer-files
fi

# Programmatically fix Composer 2.2 allow-plugins to avoid errors
composer config --no-plugins allow-plugins.composer/installers true
composer config --no-plugins allow-plugins.drupal/core-project-message true
composer config --no-plugins allow-plugins.drupal/core-vendor-hardening true
composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer config --no-plugins allow-plugins.phpstan/extension-installer true
composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
composer config --no-plugins allow-plugins.php-http/discovery true
composer config --no-plugins allow-plugins.tbachert/spi false

# packages.drupal.org adds "drupal/toolbar": "*" to admin_toolbar. Drupal core
# only declares that it replaces drupal/toolbar since 10.6.15/11.3.20/11.4.5;
# otherwise Composer falls back to the contrib Toolbar project (Drupal 11.3+).
# Provide it from the root project; unlike replace, this doesn't conflict with
# newer core releases. `composer config` can't set "provide", so use jq.
if [ "$DP_EXTRA_ADMIN_TOOLBAR" == '1' ] && [[ "$DP_CORE_VERSION" =~ ^10(\..*)?$ ]]; then
    echo "$(jq '.provide["drupal/toolbar"] = "*"' composer.json --indent 4)" >composer.json
fi

# Add project source code as symlink (to repos/name_of_project)
# double quotes explained - https://stackoverflow.com/a/1250279/5754049
if [ -n "$DP_PROJECT_NAME" ]; then
    composer --no-plugins config \
        repositories.core1 \
        '{"type": "path", "url": "repos/'"$DP_PROJECT_NAME"'", "options": {"symlink": true}}'

    composer --no-plugins config minimum-stability dev
fi

# Scaffold settings.php.
composer config -jm extra.drupal-scaffold.file-mapping '{
    "[web-root]/sites/default/settings.php": {
        "path": "web/core/assets/scaffold/files/default.settings.php",
        "overwrite": false
    }
}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $APP_ROOT/.devpanel/drupal-settings.patch || :'
