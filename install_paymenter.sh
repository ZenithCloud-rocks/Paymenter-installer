#!/bin/bash

# Install Dependencies
echo "Installing dependencies..."
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-10.11"
apt update
apt -y install php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Install Composer
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Download the code
echo "Downloading Paymenter..."
mkdir /var/www/paymenter
cd /var/www/paymenter
curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
tar -xzvf paymenter.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Install & Setup Database
echo "Setting up database..."
mysql -u root -p -e "CREATE USER 'paymenter'@'127.0.0.1' IDENTIFIED BY 'yourPassword'; CREATE DATABASE paymenter; GRANT ALL PRIVILEGES ON paymenter.* TO 'paymenter'@'127.0.0.1' WITH GRANT OPTION;"

# Environment Configuration
echo "Configuring environment..."
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan storage:link

# Database Setup
echo "Setting up database tables..."
php artisan migrate --force --seed

# Add The First User
echo "Creating admin user..."
php artisan p:user:create

# Webserver configuration
echo "Configuring Nginx..."
cat <<EOF >/etc/nginx/sites-available/paymenter.conf
server {
    listen 80;
    listen [::]:80;
    server_name paymenter.org;
    root /var/www/paymenter/public;

    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
}
EOF

ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
systemctl restart nginx

# Fix permissions
chown -R www-data:www-data /var/www/paymenter/*

# Cronjob
echo "Setting up cronjob..."
echo "* * * * * php /var/www/paymenter/artisan schedule:run >> /dev/null 2>&1" | sudo crontab -

# Create Queue Worker
echo "Setting up queue worker..."
cat <<EOF >/etc/systemd/system/paymenter.service
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

systemctl enable --now paymenter.service

echo "Installation completed successfully!"
