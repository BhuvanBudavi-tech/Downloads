#!/bin/bash

set -e

echo "[INFO] Updating packages..."
apt-get update

echo "[INFO] Installing MySQL Server..."
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server expect

echo "[INFO] Running mysql_secure_installation with predefined answers..."

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation

expect \"Press y|Y for Yes, any other key for No:\"
send \"n\r\"

expect \"New password:\"
send \"\r\"

expect \"Re-enter new password:\"
send \"\r\"

expect \"Remove anonymous users?\"
send \"y\r\"

expect \"Disallow root login remotely?\"
send \"y\r\"

expect \"Remove test database and access to it?\"
send \"y\r\"

expect \"Reload privilege tables now?\"
send \"y\r\"

expect eof
")

echo "$SECURE_MYSQL"

# Verify installation
echo "[INFO] Verifying MySQL installation..."
if systemctl status mysql | grep -q running; then
    echo "[SUCCESS] MySQL is installed and running."
else
    echo "[ERROR] MySQL installation failed or service not running." >&2
    exit 1
fi

# Setup root login script
echo "[INFO] Creating one-time root login script for MySQL user setup..."

cat << 'EOF' > /root/setup-mysql-user.sh
#!/bin/bash

echo "MySQL root user setup (run-once)"

read -p "Enter MySQL username to create: " mysql_user
read -s -p "Enter password for user '\$mysql_user': " mysql_pass
echo

mysql -u root <<MYSQL_SCRIPT
CREATE USER '\$mysql_user'@'%' IDENTIFIED BY '\$mysql_pass';
GRANT ALL PRIVILEGES ON *.* TO '\$mysql_user'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "MySQL user '\$mysql_user' created successfully."

MYSQL_CONF_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"
if grep -q "^bind-address" "\$MYSQL_CONF_FILE"; then
    sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "\$MYSQL_CONF_FILE"
else
    echo "bind-address = 0.0.0.0" >> "\$MYSQL_CONF_FILE"
fi

systemctl restart mysql
echo "MySQL configured to allow remote connections (0.0.0.0)."

sed -i '/setup-mysql-user.sh/d' /root/.bashrc
rm -- "\$0"
EOF

chmod +x /root/setup-mysql-user.sh

# Ensure the script runs once on root login
echo "/root/setup-mysql-user.sh" >> /root/.bashrc

echo "[INFO] Setup complete. Log in as root to configure MySQL user."
