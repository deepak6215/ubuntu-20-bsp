#!/bin/bash

set -x

if [ $# -lt 3 ]
then
 echo "Usage script Server_ID MySQL_DB_PASSWORD PLANT_NAME"
 exit 1
fi

SCRIPT_DIR=$(pwd)
SERVER_ID=$1
MYSQL_PASS=$2
PMA_PASS=$2
PLANT_NAME=$3
IPLON_PACKAGE_PATH="/opt/iplon"
DB="iSolar_db"

NTP_IP="192.168."$(echo $SERVER_ID | cut -c1-2).81
echo "Package Installation Starts"

installPackage() {
 for PACKAGE in "$@"; do
  if [ $(dpkg-query -W -f='${Status}' $PACKAGE 2>/dev/null | grep -c "install ok") -eq 0 ]; then
   echo "Installing $PACKAGE !"
   apt install -qq -y $PACKAGE;
  else
   echo "$PACKAGE already installed !"
  fi
 done
}

# Update Repository
apt update

# Install supporting (vim tcpdump screen unrar htop dos2uni) Packages
installPackage vim tcpdump screen unrar htop dos2unix expect ncdu sshpass net-tools 

# Install Required (openssh-server openssh-client openvpn ntp) Packages
installPackage openssh-server openssh-client openvpn ntp curl

if [ $(cat /etc/ntp.conf | grep -c $NTP_IP) -eq 0 ]; then
 sed -i '18 a server $NTP_IP' /etc/ntp.conf
fi
if [ $(cat /etc/ntp.conf | grep -c "server 0.in.pool.ntp.org") -eq 0 ]; then
 sed -i '19 a server 0.in.pool.ntp.org' /etc/ntp.conf
fi

wget https://dl.grafana.com/oss/release/grafana_7.0.6_amd64.deb
sudo dpkg -i grafana_7.0.6_amd64.deb
service grafana-server restart
service grafana-server status
wget https://dl.influxdata.com/telegraf/releases/telegraf_1.12.0-1_amd64.deb
sudo dpkg -i telegraf_1.12.0-1_amd64.deb
service telegraf restart
service telegraf status
wget https://dl.influxdata.com/influxdb/releases/influxdb_1.8.5_amd64.deb
sudo dpkg -i influxdb_1.8.5_amd64.deb
service influxdb restart
service influxdb status

curl -XPOST 'http://localhost:8086/query' --data-urlencode 'q=CREATE DATABASE "iSolar"'

apt update

# Install MySQL Server in a Non-Interactive mode. Default root password will be MYSQL_PASS
#add-apt-repository -y ppa:ondrej/mysql-5.6
cd $SCRIPT_DIR
dpkg -i mysql-apt-config_0.8.12-1_all.deb
apt update
sudo apt install -f mysql-client=5.7* mysql-community-server=5.7* mysql-server=5.7*


#ubuntu php5.5 docker container installation
apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
apt update
sudo apt install docker-ce
systemctl status docker
sleep 10
sudo docker load -i iot6_ubuntu14.tar.gz
sudo docker run --name iot6_ubuntu14.04 --net host -v /var/www/:/var/www/ -v /var/run/mysqld/:/var/run/mysqld/ -v /var/lib/mysql/:/var/lib/mysql/ -v /var/lib/snmp/:/var/lib/snmp/ -v /opt/iplon/:/opt/iplon/ -itd iot6_php5.5:2.0

#report docker container installation
docker load -i report_docker.tar.gz
docker run -d --name report-api --restart on-failure:5 -p 83:83 --network="host" report_docker:latest
sudo docker update --restart unless-stopped $(docker ps -q)

#dwagent installation
wget https://www.dwservice.net/download/dwagent_x86.sh
chmod 777 dwagent_x86.sh
./dwagent_x86.sh


apt update
# Update Repository for Nodejs
# add-apt-repository -y ppa:chris-lea/node.js
# curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
# Update Repository
# Install Nodejs Package
installPackage nodejs


# Install Samba Server
installPackage samba
if [ $(cat /etc/group | grep -c shareaccess) -eq 0 ]; then
 groupadd shareaccess
fi
useradd -m iplonshare -g shareaccess -s /usr/sbin/nologin
smbpasswd -a iplonshare <<EOF
iplonShare
iplonShare
EOF

mkdir -p /var/www/csvbackup
mkdir -p /var/www/report/export/Scheduled_Report

#mkdir -p /home/iplonshare/csvbackup
mkdir -p /home/iplonshare/Scheduled_Report
#chown -R iplonshare:shareaccess /home/iplonshare/csvbackup/
chown -R iplonshare:shareaccess /home/iplonshare/Scheduled_Report
#mount --bind /var/www/csvbackup /home/iplonshare/csvbackup
mount --bind /var/www/report/export/Scheduled_Report /home/iplonshare/Scheduled_Report
#if [ $(cat /etc/fstab | grep -c "/home/iplonshare/csvbackup") -eq 0 ]; then
# echo "# Bind csvbackup directory for samba share access" >> /etc/fstab
# echo "/var/www/csvbackup /home/iplonshare/csvbackup none     bind    0       0" >> /etc/fstab
#fi
if [ $(cat /etc/fstab | grep -c "/home/iplonshare/Scheduled_Report") -eq 0 ]; then
 echo "# Bind Scheduled_Report directory for samba share access" >> /etc/fstab
 echo "/var/www/report/export/Scheduled_Report /home/iplonshare/Scheduled_Report none     bind    0       0" >> /etc/fstab
fi

# Install FTP
installPackage vsftpd
if [ $(cat /etc/group | grep -c ftpaccess) -eq 0 ]; then
 groupadd ftpaccess
fi
useradd -m iplonftp -g ftpaccess -s /usr/sbin/nologin
passwd iplonftp <<EOF
iplonFtp
iplonFtp
EOF

mkdir -p /home/iplonftp/csvbackup
mkdir -p /home/iplonftp/Scheduled_Report
chown -R iplonftp:ftpaccess /home/iplonftp/csvbackup/
chown -R iplonftp:ftpaccess /home/iplonftp/Scheduled_Report
mount --bind /var/www/csvbackup /home/iplonftp/csvbackup
mount --bind /var/www/report/export/Scheduled_Report /home/iplonftp/Scheduled_Report
if [ $(cat /etc/fstab | grep -c "/home/iplonftp/csvbackup") -eq 0 ]; then
 echo "# Bind csvbackup directory for ftp access" >> /etc/fstab
 echo "/var/www/csvbackup /home/iplonftp/csvbackup none     bind    0       0" >> /etc/fstab
fi
if [ $(cat /etc/fstab | grep -c "/home/iplonftp/Scheduled_Report") -eq 0 ]; then
 echo "# Bind Scheduled_Report directory for ftp access" >> /etc/fstab
 echo "/var/www/report/export/Scheduled_Report /home/iplonftp/Scheduled_Report none     bind    0       0" >> /etc/fstab
fi

# Untar require files
cd $SCRIPT_DIR
tar -xJf serverData.tar.xz -C /

apt update

adduser iplon www-data
mkdir -p /var/www/iSolar/fetchDDT/csv
mkdir -p /var/log/scaback_csv_influx_ingestor
mkdir -p /var/log/prometheus
mkdir -p /var/log/iGate_log

chown www-data:www-data -R /var/www/*
chown www-data:www-data -R /var/www/.config/

chmod 755 -R /var/www/*
chmod 755 -R /var/www/.config/
chmod 777 -R /var/www/report/export/Scheduled_Report/
chmod 777 -R /var/www/iSolar/fetchDDT/csv

chown root:crontab /var/spool/cron/crontabs/root
chmod 600 /var/spool/cron/crontabs/root

chown root:root /etc/ntp.conf
chown root:root /etc/samba/smb.conf
chown root:root /etc/vsftpd.conf

chmod 644 /etc/ntp.conf
chmod 644 /etc/samba/smb.conf

chmod 644 /etc/vsftpd.conf

chmod 777 /var/log/report.log

mysql -u root -p$MYSQL_PASS -e "CREATE DATABASE IF NOT EXISTS $DB"

#sed -i "s/anlagen_id=0000/anlagen_id=$SERVER_ID/g" $IPLON_PACKAGE_PATH/scripts/vpn.sh

sed -i "s/xxx/$PLANT_NAME/g" /var/www/iSolar/fetchDDT/data.json
sed -i "s/XXX/$MYSQL_PASS/g" /var/www/iSolar/fetchDDT/data.json
sed -i "s/xxx/$MYSQL_PASS/g" /var/www/DO/db_config.php
sed -i "s/xxx/$MYSQL_PASS/g" /var/www/iSolar/powercontrol/db_config.php
sed -i "s/xxx/$MYSQL_PASS/g" /var/www/alarmlist/db_config.php



: '
if [ $(cat /etc/samba/smb.conf | grep -c "Scheduled_Report") -eq 0 ]; then
 echo "[Scheduled_Report]" >> /etc/samba/smb.conf
 echo "comment = Scheduled Report Share" >> /etc/samba/smb.conf
 echo "path = /home/iplonshare" >> /etc/samba/smb.conf
 echo "available=yes" >> /etc/samba/smb.conf
 echo "valid users = iplonshare" >> /etc/samba/smb.conf
 echo "public = yes" >> /etc/samba/smb.conf
 echo "guest ok = yes" >> /etc/samba/smb.conf
 echo "writable = yes" >> /etc/samba/smb.conf
 echo "browsable = yes" >> /etc/samba/smb.conf
 echo "read only = no" >> /etc/samba/smb.conf
 echo "create mask = 0777" >> /etc/samba/smb.conf
fi
'
: '
sed -i '0,/#local_umask=022/s/#local_umask=022/local_umask=022/g' /etc/vsftpd.conf
sed -i '0,/#chroot_local_user=YES/s/#chroot_local_user=YES/chroot_local_user=YES/' /etc/vsftpd.conf
sed -i 's/pam_service_name=vsftpd/pam_service_name=ftp/g' /etc/vsftpd.conf
if [ $(cat /etc/vsftpd.conf | grep -c "allow_writeable_chroot=YES") -eq 0 ]; then
 echo "allow_writeable_chroot=YES" >> /etc/vsftpd.conf
fi
if [ $(cat /etc/vsftpd.conf | grep -c "pasv_enable=Yes") -eq 0 ]; then
 echo "pasv_enable=Yes" >> /etc/vsftpd.conf
fi
'

#ifdown --exclude=lo -a && sudo ifup --exclude=lo -a
#service networking restart

service ssh restart
service mysql restart
service ntp restart
service scaback start
systemctl enable scaback
service readDDT start
systemctl enable readDDT

service scabackFast start
systemctl enable scabackFast
service readDDTFast start
systemctl enable readDDTFast
service smbd restart
service vsftpd restart

sleep 15

#mysql -u root -p$MYSQL_PASS iSolar_db < /home/iplon/iSolar_db.sql

sudo -s

service cron restart

echo "package Installation Finished !"
