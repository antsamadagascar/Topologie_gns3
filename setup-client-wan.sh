#!/bin/bash
# Reconfiguration de Client-WAN apres redemarrage du noeud
set -e
ip addr add 192.168.1.10/24 dev eth0 2>/dev/null || true
ip link set eth0 up
ip route add default via 192.168.1.1 2>/dev/null || true
echo "Client-WAN configure : 192.168.1.10/24, passerelle 192.168.1.1"
ip addr show eth0
