#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Copyright (C) 2026 DevPanel
# You can install any service here to support your project
# Please make sure you run apt update before install any packages
# Example:
# - apt-get update
# - apt-get install nano
#
# ----------------------------------------------------------------------
set -eu -o pipefail
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi

# Install APT packages.
if ! command -v direnv >/dev/null 2>&1; then
  apt-get update
  apt-get install -y direnv jq libtool nano npm ripgrep
fi

# Enable direnv in Bash shells and silence its startup log lines.
if ! grep -Fq '# DevPanel direnv configuration.' /etc/bash.bashrc; then
  cat >>/etc/bash.bashrc <<'EOF'

# DevPanel direnv configuration.
export DIRENV_LOG_FORMAT=
eval "$(direnv hook bash)"
EOF
fi

# Trust the project .envrc when present so vendor/bin is activated automatically.
if command -v direnv >/dev/null 2>&1 && [ -f "$APP_ROOT/.envrc" ]; then
  runuser -u "${SUDO_USER:-$USER}" -- direnv allow "$APP_ROOT" || true
fi

PHP_CONFIG_CHANGED=false
PECL_CHANNELS_UPDATED=false
PHP_VERSION_ID=$(php -r 'echo PHP_VERSION_ID;')

# Install APCU extension.
if ! php --ri apcu > /dev/null 2>&1; then
  if [ "$PHP_VERSION_ID" -ge 80600 ]; then
    if command -v pie >/dev/null 2>&1; then
      APCU_METADATA=$(curl -fsSL https://repo.packagist.org/p2/apcu/apcu.json) || exit 1
      APCU_VERSION=$(jq -er '
        first(.packages["apcu/apcu"][]?.version | strings | select(test("^v?[0-9]+(\\.[0-9]+)+$")))
        // error("No stable APCu version found on Packagist.")
      ' <<< "$APCU_METADATA")
      if [ "$APCU_VERSION" = "5.1.28" ] || [ "$APCU_VERSION" = "v5.1.28" ]; then
        echo "Skipping APCu $APCU_VERSION on PHP 8.6 or later: it is incompatible with PHP 8.6." >&2
      else
        pie -n --auto-install-build-tools install apcu/apcu
        PHP_CONFIG_CHANGED=true
      fi
    else
      echo 'Cannot install APCu: PIE is not available.' >&2
    fi
  else
    $PECL_CHANNELS_UPDATED || pecl update-channels && PECL_CHANNELS_UPDATED=true
    # Bypass question about enabling internal debugging.
    pecl install apcu <<< ''
    echo 'extension=apcu.so' > /usr/local/etc/php/conf.d/apcu.ini
    PHP_CONFIG_CHANGED=true
  fi
fi
# Install uploadprogress extension.
if ! php --ri uploadprogress > /dev/null 2>&1; then
  if [ "$PHP_VERSION_ID" -ge 80600 ]; then
    echo 'Skipping uploadprogress on PHP 8.6 or later: installation is not yet supported.' >&2
  else
    $PECL_CHANNELS_UPDATED || pecl update-channels && PECL_CHANNELS_UPDATED=true
    pecl install uploadprogress
    echo 'extension=uploadprogress.so' > /usr/local/etc/php/conf.d/uploadprogress.ini
    PHP_CONFIG_CHANGED=true
  fi
fi
# Disable Xdebug if it's enabled, as it can interfere with performance and is
# not needed in production.
if [ -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini ]; then
  rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && PHP_CONFIG_CHANGED=true
fi
# Enable JIT if not already enabled, as it can improve performance for Drupal.
if ! php --ri 'Zend OPcache' | grep 'opcache.enable => On' > /dev/null 2>&1; then
  echo 'opcache.jit=tracing' > /usr/local/etc/php/conf.d/opcache.ini \
    && PHP_CONFIG_CHANGED=true
fi
# Reload Apache if it's running.
if $PHP_CONFIG_CHANGED && /etc/init.d/apache2 status > /dev/null; then
  /etc/init.d/apache2 reload
fi

# Install the DrupalPod VS Code extension for code-server.
if [[ "$CODES_ENABLE" == "yes" ]]; then
  DRUPALPOD_EXT=drupal-mentoring.drupalpod-ext
  if [ -z "$(find "$CODES_USER_DATA_DIR/extensions/" -maxdepth 1 -iname "${DRUPALPOD_EXT}-*" -type d 2>/dev/null)" ]; then
    sudo -u "${SUDO_USER:-$USER}" -E -- code-server --install-extension "$DRUPALPOD_EXT" --user-data-dir="$CODES_USER_DATA_DIR"
  fi
fi

if [ -f "$APP_ROOT/.devpanel/crontab" ]; then
  # Install supercronic.
  if ! command -v supercronic >/dev/null 2>&1; then
    curl -fsSL "https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-$(dpkg --print-architecture)" \
      -o /usr/local/bin/supercronic
    chmod +x /usr/local/bin/supercronic
  fi
  # Load project cron file.
  if command -v supercronic >/dev/null 2>&1; then
    # Start only if no existing supercronic is watching this file.
    if ! pgrep -f "supercronic -inotify ${APP_ROOT}/\.devpanel/crontab" >/dev/null 2>&1; then
      echo "Starting supercronic to watch ${APP_ROOT}/.devpanel/crontab"
      runuser -u "${SUDO_USER:-$USER}" -- supercronic -inotify "$APP_ROOT/.devpanel/crontab" &
    fi
  fi
fi

rm -rf /var/lib/apt/lists/*
