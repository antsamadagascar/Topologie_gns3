#!/bin/bash
# Reconfiguration de Serveur-Web apres redemarrage du noeud
set -e
ip addr add 192.168.2.10/24 dev eth0 2>/dev/null || true
ip link set eth0 up
ip route add default via 192.168.2.1 2>/dev/null || true

# Redemarrer Nginx
pkill nginx 2>/dev/null || true
sleep 1
nginx

# Recree le fichier de test pour la demo de limitation de bande passante
dd if=/dev/urandom of=/var/www/html/testfile.bin bs=1M count=10 2>/dev/null

echo "Serveur-Web configure : 192.168.2.10/24, passerelle 192.168.2.1"
ip addr show eth0
ps aux | grep nginx | grep -v grep
