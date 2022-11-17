#!/usr/bin/env bash

echo "Script enhanced by Cameron Kilton at Nextlink Internet (wwww.nextlinkinternet.com) Orignal from hdkmike"
echo "Enter the version number of Netbox you would like to intall? : "
read VERSION
echo "Version ${VERSION} will be intsalled"
URL=https://github.com/digitalocean/netbox/archive/v${VERSION}.tar.gz
CURDIR='pwd'

# Install pre-requisites
sudo apt update
sudo apt-get install -y postgresql
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Setup postgres
sudo -u postgres psql < ${CURDIR}/conf/postgres.conf

# Install app pre-requisites
sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential libxml2-dev libxslt1-dev libffi-dev libpq-dev libssl-dev zlib1g-dev
sudo pip install --upgrade pip

# Install redis server
sudo apt install -y redis-server

# Download and install app
mkdir /tmp/netbox/
cd /tmp/netbox/
wget ${URL}
tar xzvf v${VERSION}.tar.gz -C /opt/
sudo ln -s /opt/netbox-${VERSION} /opt/netbox

# Install app requirements
cd /opt/netbox/
sudo pip install -r requirements.txt

# Setup configuration
cd netbox/netbox/

# Postgres password setup
dbpass=0
if [ $dbpass = 0 ]; then
        dbpass='sudo cat /dev/random'
        dbpass=$(head -c 25 /dev/random | base64)
        echo $dbpass
fi
sudo sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = \['*'\]/" /opt/netbox/netbox/netbox/configuration.py
sudo sed -i "s/'USER': '',/'USER': 'netbox',/" /opt/netbox/netbox/netbox/configuration.py
sudo sed -i "s/'PASSWORD': '',           # PostgreSQL password/'PASSWORD': '${dbpass}',/" /opt/netbox/netbox/netbox/configuration.py

PRIVATE_KEY=0
if [ $PRIVATE_KEY = 0 ]; then
        PRIVATE_KEY='sudo cat /dev/random'
        PRIVATE_KEY=$(head -c 50 /dev/random | base64)
        echo $PRIVATE_KEY
fi
sudo sed -i "s/SECRET_KEY = ''/SECRET_KEY = '${PRIVATE_KEY}'/" /opt/netbox/netbox/netbox/configuration.py

echo "Please Enter the following commands and copy the 25 character db passowrd above"
echo "CREATE DATABASE netbox; "
echo "CREATE USER netbox WITH PASSWORD 'The 25 character password';"
echo "GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;"
echo "Type \q when you are completed"
sudo -u postgres psql

echo "Completed with database setup"

# Run database migrations
cd /opt/netbox/netbox/
sudo python3 manage.py migrate

# Create super user
sudo python3 manage.py createsuperuser

# Collect static files
sudo python3 manage.py collectstatic

# Install webservers
sudo apt-get install -y gunicorn supervisor nginx

# Configure gunicorn
sudo cp /opt/netbox/contrib/gunicorn.py /opt/netbox/gunicorn.py
sudo cp -v /opt/netbox/contrib/*.service /etc/systemd/system/
sudo systemctl daemon-reload

sudo systemctl start netbox netbox-rq
sudo systemctl enable netbox netbox-rq

# Configure SSL for webserver
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
-keyout /etc/ssl/private/netbox.key \
-out /etc/ssl/certs/netbox.crt

# Configure webservers
sudo cp /opt/netbox/contrib/nginx.conf /etc/nginx/sites-available/netbox     
sudo rm /etc/nginx/sites-enabled/default
echo "If remove error, default may already have been removed"
sudo ln -s /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/netbox     
sudo systemctl restart nginx

echo "DONE"
