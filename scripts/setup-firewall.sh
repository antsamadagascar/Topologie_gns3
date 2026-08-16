#!/bin/bash
# =========================================================
# Script de reconfiguration COMPLETE du pare-feu Firewall-3if-1
# A relancer a chaque redemarrage du noeud (les commandes ip/
# iptables/tc/squid/snort ne sont pas persistantes dans le
# conteneur Docker apres un arret complet de GNS3).
#
# Usage :
#   docker cp scripts/setup-firewall.sh <container_id>:/root/
#   (puis, dans la console GNS3 du pare-feu)
#   bash /root/setup-firewall.sh
#
# =========================================================
set -e

echo "=== 1. Adressage IP des 3 interfaces du pare-feu ==="

# le pare-feu aura 3 interfaces (WAN, DMZ, LAN)
ip addr add 192.168.1.1/24 dev eth0 2>/dev/null || true   # eth0 = WAN
ip addr add 192.168.2.1/24 dev eth1 2>/dev/null || true   # eth1 = DMZ
ip addr add 192.168.3.1/24 dev eth2 2>/dev/null || true   # eth2 = LAN
ip link set eth0 up
ip link set eth1 up
ip link set eth2 up

echo "=== 2. Activation du routage IP ==="
# Prerequis technique : necessaire pour que le pare-feu fasse
# transite le trafic entre les 3 sous-reseaux
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "=== 3. Reinitialisation des regles iptables ==="
iptables -F
iptables -t nat -F
iptables -P FORWARD ACCEPT   # ACCEPT temporaire, le temps d'ajouter les regles (verrouillage a l'etape 11)

echo "=== 4. Regles FORWARD ==="
# "Autoriser le trafic deja etabli" (necessaire pour que
# les reponses aux connexions autorisees puissent revenir)
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# "Autoriser HTTP, HTTPS, SSH vers la DMZ (depuis WAN et LAN)"
# -- depuis le WAN --
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 22  -j ACCEPT
# -- depuis le LAN --
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -p tcp --dport 22  -j ACCEPT

# "Autoriser le LAN a sortir vers l'exterieur via NAT"
# (partie filtrage ; le NAT proprement dit est a l'etape 5)
iptables -A FORWARD -i eth2 -o eth0 -j ACCEPT

# "Bloquer l'acces du WAN vers le LAN"
# Test attendu : "WAN ne peut pas ping ou acceder au LAN"
iptables -A FORWARD -i eth0 -o eth2 -j DROP

# Remarque : aucune regle ACCEPT n'est ajoutee pour du trafic
# initie depuis eth1 (DMZ) vers eth0/eth2 -> combine avec la
# politique par defaut DROP (etape 11), cela satisfait :
# Exigence sujet Serveur Web : "Ne peut initier aucune connexion sortante"

echo "=== 5. NAT + redirection transparente vers Squid ==="
# "Autoriser le LAN a sortir vers l'exterieur via NAT"
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.3.0/24 -j MASQUERADE

# Prerequis technique pour les exigences de filtrage de contenu
# (etape 7, sites pornographiques / Facebook / YouTube) : rediriger
# tout le trafic HTTP du LAN vers le proxy Squid, sans configuration
# manuelle sur chaque poste client (proxy transparent)
iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 80 -j REDIRECT --to-port 3128

echo "=== 6. Limitation de bande passante ==="
# "Limitation de la bande passante a 500 Ko/s par machine LAN"
tc qdisc del dev eth2 root 2>/dev/null || true
tc qdisc add dev eth2 root handle 1: htb default 30
tc class add dev eth2 parent 1: classid 1:1 htb rate 500kbps
tc class add dev eth2 parent 1:1 classid 1:30 htb rate 500kbps ceil 500kbps

echo "=== 7. Configuration Squid : filtrage de contenu ==="
mkdir -p /etc/squid
cat > /etc/squid/squid.conf << 'SQUIDEOF'
# Port non-intercepte, requis pour le fonctionnement interne de Squid
http_port 3129
# Port intercepte : recoit le trafic redirige par iptables (etape 5)
http_port 3128 intercept

acl localnet src 192.168.3.0/24

# Exigence sujet : "Bloquer l'acces a Facebook et YouTube pendant
# les heures de travail (8h-12h, 14h-18h)"
# Heures calculees en UTC (le conteneur n'a pas de vraie tzdata) :
# Madagascar = UTC+3 -> 08:00-12:00 locale = 05:00-09:00 UTC
#                       14:00-18:00 locale = 11:00-15:00 UTC
acl heures_bureau_matin time 05:00-09:00
acl heures_bureau_apresmidi time 11:00-15:00
acl reseaux_sociaux dstdomain .facebook.com .youtube.com
http_access deny reseaux_sociaux heures_bureau_matin
http_access deny reseaux_sociaux heures_bureau_apresmidi

# Exigence sujet : "Bloquer les sites pornographiques (SquidGuard
# ou autre blacklist)" -- ici : liste noire Squid (acl dstdomain)
acl sites_adultes dstdomain "/etc/squid/blacklist_adultes.txt"
http_access deny sites_adultes

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

echo "=== 8. Configuration Snort : IDS ==="
# Exigence sujet : "Surveillance IDS avec Snort : detecter scan de
# ports, attaques courantes, connexions anormales ; journaliser et
# expliquer les alertes generees"
mkdir -p /etc/snort/rules /var/log/snort
cat > /etc/snort/rules/local.rules << 'SNORTRULESEOF'
# Test attendu par le sujet : "Snort doit detecter une tentative
# de scan de ports depuis WAN" -> seuil : 5 paquets SYN de la meme
# source vers HOME_NET en moins de 10 secondes = signature de scan
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
# Ecoute sur eth0 (WAN) : conforme au test "Snort doit detecter
# une tentative de scan de ports depuis WAN"
pkill -9 -f snort 2>/dev/null || true
nohup snort -c /etc/snort/snort.conf -i eth0 -A fast -l /var/log/snort > /var/log/snort/snort-stdout.log 2>&1 &

echo "=== 11. Verrouillage final de la politique FORWARD ==="
# "Bloque tout autre port ou protocole par defaut"
# Fait en dernier (apres validation des regles ACCEPT) pour ne pas
# se couper l'acces en cours de configuration.
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