#!/bin/bash

# Function to install Paymenter
install_paymenter() {
    echo "Starting Paymenter installation..."

    # Prompt user for configuration options
    read -p "Enter database name: " dbname
    read -p "Enter database username: " dbuser
    read -sp "Enter database password: " dbpass
    echo
    read -p "Enter domain name: " domain

    # Install dependencies
    echo "Installing dependencies..."
    sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-10.11"
    sudo apt update
    sudo apt -y install php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

    # Install Composer
    echo "Installing Composer..."
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

    # Download the code
    echo "Downloading Paymenter..."
    sudo mkdir -p /var/www/paymenter
    sudo chown -R $USER:$USER /var/www/paymenter
    cd /var/www/paymenter
    curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
    tar -xzvf paymenter.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    # Install & Setup Database
    echo "Setting up database..."
    sudo mysql -u root -p$dbpass -e "CREATE DATABASE IF NOT EXISTS $dbname; \
                                     CREATE USER IF NOT EXISTS '$dbuser'@'localhost' IDENTIFIED BY '$dbpass'; \
                                     GRANT ALL PRIVILEGES ON $dbname.* TO '$dbuser'@'localhost'; \
                                     FLUSH PRIVILEGES;"

    # Environment Configuration
    echo "Configuring environment..."
    cp .env.example .env
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$dbname/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$dbuser/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$dbpass/" .env
    sed -i "s|APP_URL=.*|APP_URL=http://$domain|" .env
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
    sudo tee /etc/nginx/sites-available/paymenter.conf > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root /var/www/paymenter/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
    sudo systemctl restart nginx

    # Fix permissions
    sudo chown -R www-data:www-data /var/www/paymenter/*

    # Cronjob
    echo "Setting up cronjob..."
    (crontab -l ; echo "* * * * * php /var/www/paymenter/artisan schedule:run >> /dev/null 2>&1") | sort - | uniq - | crontab -

    # Create Queue Worker
    echo "Setting up queue worker..."
    sudo tee /etc/systemd/system/paymenter.service > /dev/null <<EOF
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

    sudo systemctl enable --now paymenter.service

    echo "Paymenter installation completed successfully!"
}

# Function to uninstall Paymenter
uninstall_paymenter() {
    echo "Starting Paymenter uninstallation..."

    # Remove Nginx configuration
    sudo rm /etc/nginx/sites-enabled/paymenter.conf
    sudo systemctl restart nginx

    # Remove Queue Worker service
    sudo systemctl disable --now paymenter.service
    sudo rm /etc/systemd/system/paymenter.service

    # Remove database
    read -p "Enter database name to delete: " dbname
    read -p "Enter database username: " dbuser
    read -sp "Enter database password: " dbpass
    echo
    sudo mysql -u $dbuser -p$dbpass -e "DROP DATABASE IF EXISTS $dbname; DROP USER IF EXISTS '$dbuser'@'localhost';"

    # Remove installation directory
    sudo rm -rf /var/www/paymenter

    echo "Paymenter uninstallation completed successfully!"
}

# Display menu options
echo "Paymenter Installer"
echo "1. Install Paymenter"
echo "2. Uninstall Paymenter"
read -p "Enter your choice: " choice

# Handle user's choice
case $choice in
    1)
        install_paymenter
        ;;
    2)
        uninstall_paymenter
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
