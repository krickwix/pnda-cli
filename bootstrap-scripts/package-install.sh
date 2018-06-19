#!/bin/bash -v

set -ex

if [ "x$REJECT_OUTBOUND" == "xYES" ]; then
PNDA_MIRROR_IP=$(echo $PNDA_MIRROR | awk -F'[/:]' '/http:\/\//{print $4}')

# Log the global scope IP connection.
cat > /etc/rsyslog.d/10-iptables.conf <<EOF
:msg,contains,"[ipreject] " /var/log/iptables.log
STOP
EOF
sudo service rsyslog restart
iptables -F LOGGING | true
iptables -F OUTPUT | true
iptables -X LOGGING | true
iptables -N LOGGING
iptables -A OUTPUT -j LOGGING
## Accept all local scope IP packets.
  ip address show  | awk '/inet /{print $2}' | while IFS= read line; do \
iptables -A LOGGING -d  $line -j ACCEPT
  done
## Log and reject all the remaining IP connections.
iptables -A LOGGING -j LOG --log-prefix "[ipreject] " --log-level 7 -m state --state NEW
iptables -A LOGGING -d  $PNDA_MIRROR_IP/32 -j ACCEPT # PNDA mirror
if [ "x$CLIENT_IP" != "x" ]; then
iptables -A LOGGING -d  $CLIENT_IP/32 -j ACCEPT # PNDA client
fi
if [ "x$NTP_SERVERS" != "x" ]; then
NTP_SERVERS=$(echo "$NTP_SERVERS" | sed -e 's|[]"'\''\[ ]||g')
iptables -A LOGGING -d  $NTP_SERVERS -j ACCEPT # NTP server
fi
if [ "x$networkCidr" != "x" ]; then
iptables -A LOGGING -d  ${networkCidr} -j ACCEPT
fi
if [ "x$privateSubnetCidr" != "x" ]; then
iptables -A LOGGING -d  ${privateSubnetCidr} -j ACCEPT
fi
iptables -A LOGGING -j REJECT --reject-with icmp-net-unreachable
iptables-save > /etc/iptables.conf
echo -e '#!/bin/sh\niptables-restore < /etc/iptables.conf' > /etc/rc.local
chmod +x /etc/rc.d/rc.local | true
fi

DISTRO=$(cat /etc/*-release|grep ^ID\=|awk -F\= {'print $2'}|sed s/\"//g)


cat << EOF > /etc/yum.repos.d/pnda_mirror.repo

[pnda_mirror]
name=added from: $PNDA_MIRROR/mirror_rpm
baseurl=$PNDA_MIRROR/mirror_rpm
enabled=1
priority = 1
gpgcheck = 1
keepcache = 0

EOF

cat > /etc/yum/pluginconf.d/fastestmirror.conf << EOF
[main]
enabled=0
EOF

yum-config-manager --disable base
yum-config-manager --disable extras
yum-config-manager --disable updates

chmod -v a-w /etc/yum.repos.d
ls -l /etc/yum.repos.d/

if [ "x$DISTRO" == "xrhel" ]; then
  rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-redhat-release
fi
rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-mysql
rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-cloudera
rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-EPEL-7
rpm --import $PNDA_MIRROR/mirror_rpm/SALTSTACK-GPG-KEY.pub
rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-CentOS-7
rpm --import $PNDA_MIRROR/mirror_rpm/RPM-GPG-KEY-Jenkins

PIP_INDEX_URL="$PNDA_MIRROR/mirror_python/simple"
TRUSTED_HOST=$(echo $PIP_INDEX_URL | awk -F'[/:]' '/http:\/\//{print $4}')
cat << EOF > /etc/pip.conf
[global]
index-url=$PIP_INDEX_URL
trusted-host=$TRUSTED_HOST
EOF
cat << EOF > /root/.pydistutils.cfg
[easy_install]
index_url=$PIP_INDEX_URL
EOF
