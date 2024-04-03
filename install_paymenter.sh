#!/bin/bash

# Define variables
DOMAIN="your_domain.com"
DB_NAME="paymenter"
DB_USER="paymenter"
DB_PASSWORD="yourPassword"
LOGO="
\033[1;36m  ____            _        _       _       
 |  _ \ ___   ___| | _____| |_ ___| |_ ___ 
 | |_) / _ \ / __| |/ / _ \ __/ __| __/ __|
 |  __/ (_) | (__|   <  __/ || (__| |_\__ \\
 |_|   \___/ \___|_|\_\___|\__\___|\__|___/
\033[0m"

# Print logo
echo -e "$LOGO"

# Function to install Paymenter
install_paymenter() {
    # Update system packages
    echo -e "\033[1;34mUpdating system packages...\033[0m"
    apt update && apt upgrade -y

    # Install dependencies
    echo -e "\033[1;34mInstalling dependencies...\033[0m"
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    apt update
    apt -y install php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

    # Install Composer
    echo -e "\033[1;34mInstalling Composer...\033[0m"
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

    # Clone the Paymenter repo
    echo -e "\033[1;34mCloning Paymenter repository...\033[0m"
    mkdir /var/www/paymenter
    cd /var/www/paymenter
    curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
    tar -xzvf paymenter.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    # Setup database
    echo -e "\033[1;34mSetting up database...\033[0m"
    mysql -u root -p -e "CREATE DATABASE $DB_NAME;"
    mysql -u root -p -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -p -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;"

    # Copy environment file and generate application key
    echo -e "\033[1;34mConfiguring environment...\033[0m"
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    php artisan storage:link

    # Configure database connection
    echo -e "\033[1;34mConfiguring database connection...\033[0m"
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env

    # Run migrations and seed data
    echo -e "\033[1;34mRunning migrations and seeding data...\033[0m"
    php artisan migrate --force --seed

    # Create administrative user
    echo -e "\033[1;34mCreating administrative user...\033[0m"
    php artisan p:user:create

    # Install Let's Encrypt SSL
    echo -e "\033[1;34mInstalling Let's Encrypt SSL certificate...\033[0m"
    apt -y install certbot python3-certbot-nginx
    certbot --nginx -d $DOMAIN

    # Setup nginx configuration
    echo -e "\033[1;34mConfiguring Nginx...\033[0m"
    cat > /etc/nginx/sites-available/paymenter.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    root /var/www/paymenter/public;

    index index.php;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
}
EOF

    # Enable site and restart nginx
    ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
    systemctl restart nginx

    # Fix permissions
    echo -e "\033[1;34mFixing permissions...\033[0m"
    chown -R www-data:www-data /var/www/paymenter/*

    # Setup cronjob
    echo -e "\033[1;34mSetting up cronjob...\033[0m"
    echo "* * * * * php /var/www/paymenter/artisan schedule:run >> /dev/null 2>&1" | sudo crontab -

    # Create queue worker service
    echo -e "\033[1;34mCreating queue worker service...\033[0m"
    cat > /etc/systemd/system/paymenter.service <<EOF
[Unit]
Description=Paymenter Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/paymenter/artisan queue:work
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start queue worker service
    systemctl enable --now paymenter.service

    echo -e "\033[1;32mPaymenter installation completed successfully!\033[0m"
}

# Function to uninstall Paymenter
uninstall_paymenter() {
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
}

# Main menu
echo -e "\033[1;32mWelcome to the Paymenter installation/uninstallation script!\033[0m"
echo "Please select an option:"
echo "1. Install Paymenter"
echo "2. Uninstall Paymenter"
read -p "Enter your choice (1 or 2): " choice

# Execute selected option
case $choice in
    1) install_paymenter ;;
    2) uninstall_paymenter ;;
    *) echo -e "\033[1;31mInvalid choice. Exiting...\033[0m" ;;
esac

exit 0
