#!/bin/bash

.
    # Stop and disable queue worker service
    systemctl stop paymenter.service
    systemctl disable paymenter.service

    # Remove queue worker service file
    rm -f /etc/systemd/system/paymenter.service

    # Remove Nginx configuration
    rm -f /etc/nginx/sites-available/paymenter.conf
    rm -f /etc/nginx/sites-enabled/paymenter.conf

    # Remove Let's Encrypt SSL certificate
    certbot delete --cert-name $DOMAIN

    # Drop database and user
    mysql -u root -p -e "DROP DATABASE IF EXISTS $DB_NAME;"
    mysql -u root -p -e "DROP USER IF EXISTS '$DB_USER'@'127.0.0.1';"

    # Remove Paymenter directory
    rm -rf /var/www/paymenter

    echo -e "\033[1;32mPaymenter has been successfully uninstalled!\033[0m"

# You can call this function wherever you need to uninstall Paymenter.
# For example:
uninstall_paymenter
