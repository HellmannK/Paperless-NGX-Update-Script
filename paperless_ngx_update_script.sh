#!/bin/bash

# Open the corresponding paperless-ngx_update_script.conf first and edit to your needs. 
# IMPORTANT: the $INSTALLATION_PATH set in the config-file should only contain the root folder. Set the absolute path here in this script at every section

CONFIG_FILE="/home/admin/paperlessUpdateScript/paperless-ngx_update_script.conf"

# Print welcome message
echo ""
echo "#############################################"
echo "###   paperless-ngx update-script         ###"
echo "#############################################"
echo ""
echo "This script will first run apt update"

# Check if the script is running as root, if not, request root access
if [ "$EUID" -ne 0 ]; then
  echo "Requesting root access..."
  echo ""
  exec sudo "$0" "$@"
fi

# Check if curl is installed
if ! command -v curl >/dev/null 2>&1; then
  echo "curl seems not to be installed. Please check and exit."
  exit
fi

# Update package list and show upgradable packages
sudo apt-get update
UPGRADEABLE_PACKAGES=$(sudo apt-get -u upgrade --assume-no | grep -c '^Inst')

if [ "$UPGRADEABLE_PACKAGES" -eq 0 ]; then
  echo "No upgrades available, skipping apt upgrade."
  echo ""
else
  # Confirm if the user wants to upgrade
  read -p "Do you want to run apt upgrade? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo apt-get upgrade
  fi
fi

echo ""
echo "#############################################"
echo "###     Starting paperless-ngx update     ###"
echo "#############################################"
echo ""

# Load configuration file
source $CONFIG_FILE

# Stop all paperless-ngx systemd services
systemctl stop paperless-task-queue.service paperless-consumer.service paperless-webserver.service paperless-scheduler.service

# Check if the backup folder exists, create it if not
mkdir -p "$BACKUP_PATH"

# Backup existing installation
echo "Creating backup..."
echo ""
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="${DATE}_PAPERLESS-NGX.bak.tar.gz"
tar -czf "$BACKUP_PATH/$BACKUP_FILENAME" -C "$INSTALLATION_PATH" paperless

# Save current paperless.conf
cp "$INSTALLATION_PATH/paperless/paperless.conf" /tmp/

# Save current /scripts folder
cp -R "$INSTALLATION_PATH/paperless/scripts" /tmp/

# Save current /nltk_data folder
cp -R "$INSTALLATION_PATH/paperless/nltk_data" /tmp/

# Save current /venv folder
cp -R "$INSTALLATION_PATH/paperless/venv" /tmp/

# Delete the original folder
rm -rf "$INSTALLATION_PATH/paperless"

# Download the latest paperless-ngx release
echo "Downloading"
echo ""
DOWNLOAD_URL=$(curl -s "$RELEASE_URL" | grep 'browser_download_url' | cut -d\" -f4)
curl -# -L -o /tmp/paperless-ngx.tar.gz "$DOWNLOAD_URL"
echo -e "\nDownload complete!"
echo ""

# Extract the downloaded release
mkdir -p "$INSTALLATION_PATH/paperless"
tar -xf /tmp/paperless-ngx.tar.gz -C "$INSTALLATION_PATH/paperless" --strip-components=1

# Copy systemd service files from backup
cp -R /tmp/scripts "$INSTALLATION_PATH/paperless"

# Copy nltk_data folder from backup
cp -R /tmp/nltk_data "$INSTALLATION_PATH/paperless"

# Copy venv folder from backup
cp -R /tmp/venv "$INSTALLATION_PATH/paperless"

# Copy the config file back to the updated folder
cp /tmp/paperless.conf "$INSTALLATION_PATH/paperless/paperless.conf"

# Ask user if they want to open the config file with nano
read -p "Do you want to open the config file with nano? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  nano "$INSTALLATION_PATH/paperless/paperless.conf"
fi

# Set ownership of the installation directory
chown -R paperless "$INSTALLATION_PATH/paperless"
chown paperless:paperless "$INSTALLATION_PATH/paperless"

# Execute commands as paperless user
sudo -u paperless bash <<EOF
# Enter venv
cd "$INSTALLATION_PATH/paperless"
source venv/bin/activate

# Update pip and install requirements
pip3 install --upgrade pip
pip3 install --upgrade -r requirements.txt

# Run database migration
cd "$INSTALLATION_PATH/paperless/src"
python3 manage.py makemigrations
python3 manage.py migrate

# leave venv
deactivate
EOF

# Reload Restart all systemd services
systemctl daemon-reload
systemctl restart paperless-task-queue.service paperless-consumer.service paperless-webserver.service paperless-scheduler.service
sleep 15

# Check if all services are running
SERVICES_STATUS=$(sudo systemctl is-active paperless-task-queue.service paperless-consumer.service paperless-webserver.service paperless-scheduler.service)
STATUS_ARRAY=($SERVICES_STATUS)

# Check if all services are active
ALL_ACTIVE=true
for STATUS in "${STATUS_ARRAY[@]}"; do
  if [[ "$STATUS" != "active" ]]; then
    ALL_ACTIVE=false
    break
  fi
done

if [ "$ALL_ACTIVE" = true ]; then
  echo ""
  echo "#############################################"
  echo "###          All services are running.    ###"
  echo "###        Update successful. Exiting...  ###"
  echo "#############################################"
  echo ""
else
  echo "Some services are not running. Please check."
fi

# Remove temporary files
rm /tmp/paperless.conf
rm /tmp/paperless-ngx.tar.gz
rm -r /tmp/scripts
rm -r /tmp/nltk_data
rm -r /tmp/venv
