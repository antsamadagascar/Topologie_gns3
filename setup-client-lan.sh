#!/bin/bash
# Reconfiguration de Client-LAN apres redemarrage du noeud
set -e
ip addr add 192.168.3.10/24 dev eth0 2>/dev/null || true
ip link set eth0 up
ip route add default via 192.168.3.1 2>/dev/null || true

# Entrees /etc/hosts pour demontrer le filtrage Squid (reseau isole, pas de vrai DNS)
grep -q "www.facebook.com" /etc/hosts || echo "192.168.2.10 www.facebook.com" >> /etc/hosts
grep -q "www.playboy.com" /etc/hosts || echo "192.168.2.10 www.playboy.com" >> /etc/hosts

echo "Client-LAN configure : 192.168.3.10/24, passerelle 192.168.3.1"
ip addr show eth0
