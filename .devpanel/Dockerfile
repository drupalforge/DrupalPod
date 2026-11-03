ENV COMPOSER_HOME="${HOME}/.config/composer"

USER root

RUN bash "$APP_ROOT/.devpanel/custom_package_installer.sh"

USER ${USER}
