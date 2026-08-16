#!/bin/bash
# =========================================================
# Script de reconfiguration COMPLETE du pare-feu Firewall-3if-1
# A relancer a chaque redemarrage du noeud (les commandes ip/
# iptables/tc ne sont pas persistantes dans le conteneur Docker)
#
# Usage : copier ce script dans le conteneur puis l'executer
#   docker cp setup-firewall.sh <container_id>:/root/
#   (dans la console GNS3 du pare-feu)
#   bash /root/setup-firewall.sh
# =========================================================
set -e
echo "=== 1. Adressage IP ==="
ip addr add 192.168.1.1/24 dev eth0 2>/dev/null || true
ip addr add 192.168.2.1/24 dev eth1 2>/dev/null || true
ip addr add 192.168.3.1/24 dev eth2 2>/dev/null || true
ip link set eth0 up
ip link set eth1 up
ip link set eth2 up

echo "=== 2. Routage IP ==="
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "=== 3. Reinitialisation des regles iptables ==="
iptables -F
iptables -t nat -F
iptables -P FORWARD ACCEPT   # on remet ACCEPT temporairement le temps d'ajouter les regles

echo "=== 4. Regles FORWARD ==="
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 22  -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 22  -j ACCEPT
iptables -A FORWARD -i eth2 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth2 -j DROP

echo "=== 5. NAT (LAN vers Internet) + redirection transparente Squid ==="
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.3.0/24 -j MASQUERADE
iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 80 -j REDIRECT --to-port 3128

echo "=== 6. Limitation de bande passante (500 Ko/s sur le LAN) ==="
tc qdisc del dev eth2 root 2>/dev/null || true
tc qdisc add dev eth2 root handle 1: htb default 30
tc class add dev eth2 parent 1: classid 1:1 htb rate 500kbps
tc class add dev eth2 parent 1:1 classid 1:30 htb rate 500kbps ceil 500kbps

echo "=== 7. Configuration Squid (reecriture complete du fichier) ==="
mkdir -p /etc/squid
cat > /etc/squid/squid.conf << 'SQUIDEOF'
http_port 3129
http_port 3128 intercept

acl localnet src 192.168.3.0/24

# Heures de bureau (calculees en UTC : Madagascar = UTC+3)
# 08:00-12:00 locale -> 05:00-09:00 UTC
# 14:00-18:00 locale -> 11:00-15:00 UTC
acl heures_bureau_matin time 05:00-09:00
acl heures_bureau_apresmidi time 11:00-15:00

acl reseaux_sociaux dstdomain .facebook.com .youtube.com

acl sites_adultes dstdomain "/etc/squid/blacklist_adultes.txt"

http_access deny sites_adultes
http_access deny reseaux_sociaux heures_bureau_matin
http_access deny reseaux_sociaux heures_bureau_apresmidi

http_access allow localnet
http_access allow localhost
http_access deny all
SQUIDEOF

cat > /etc/squid/blacklist_adultes.txt << 'BLACKEOF'
.xxx
.adult-example.com
.playboy.com
.pornhub.com
BLACKEOF

echo "=== 8. Configuration Snort (reecriture complete) ==="
mkdir -p /etc/snort/rules /var/log/snort
cat > /etc/snort/rules/local.rules << 'SNORTRULESEOF'
alert tcp any any -> $HOME_NET any (msg:"Possible scan de ports detecte"; flags:S; threshold: type threshold, track by_src, count 5, seconds 10; sid:1000001; rev:1;)
alert icmp any any -> $HOME_NET any (msg:"Ping ICMP detecte"; sid:1000002; rev:1;)
SNORTRULESEOF

cat > /etc/snort/snort.conf << 'SNORTCONFEOF'
ipvar HOME_NET [192.168.2.0/24,192.168.3.0/24]
ipvar EXTERNAL_NET any

include /etc/snort/rules/local.rules

output alert_fast: /var/log/snort/alert.log
SNORTCONFEOF

echo "=== 9. Demarrage de Squid ==="
pkill -9 -f squid 2>/dev/null || true
sleep 1
rm -f /run/squid.pid
squid -z 2>/dev/null || true
squid

echo "=== 10. Demarrage de Snort (ecoute sur eth0/WAN) ==="
pkill -9 -f snort 2>/dev/null || true
nohup snort -c /etc/snort/snort.conf -i eth0 -A fast -l /var/log/snort > /var/log/snort/snort-stdout.log 2>&1 &

echo "=== 11. VERROUILLAGE FINAL (a faire en dernier, une fois tout teste) ==="
iptables -P FORWARD DROP

echo ""
echo "=== Configuration terminee (IP + iptables + NAT + tc + Squid + Snort) ==="
echo "Verifications utiles :"
echo "  ip addr show"
echo "  iptables -L FORWARD -v -n"
echo "  iptables -t nat -L -v -n"
echo "  tc class show dev eth2"
echo "  ps aux | grep -E 'squid|snort'"
echo "  cat /etc/squid/squid.conf"