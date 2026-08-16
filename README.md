# README — TP DMZ : démarrage et tests

## 1. Ouvrir GNS3 et démarrer les nœuds
```
gns3 → ouvrir le projet → clic droit → Start all nodes
```
Attendre ~15 secondes.

## 2. Charger la config sur chaque nœud (1 seule fois par redémarrage de nœud)

Si le script est déjà sauvegardé (`/root/setup-*.sh` présent) :
```bash
bash /root/setup-firewall.sh      # console Firewall-3if-1
bash /root/setup-client-wan.sh    # console Client-WAN
bash /root/setup-serveur-web.sh   # console Serveur-Web
bash /root/setup-client-lan.sh    # console Client-LAN
```

## 3. Vérification rapide (console Firewall-3if-1)
```bash
ip addr show
iptables -L FORWARD -v -n
iptables -t nat -L -v -n
tc class show dev eth2
ps aux | grep -E 'squid|snort'
```

## 4. Tests fonctionnels

> Rappel du sujet (section « Tests à Réaliser ») :
> ✅ WAN peut accéder à la page web de la DMZ. / ❌ WAN ne peut pas ping ou accéder au LAN. /
> ✅ LAN peut accéder à Internet et à la DMZ. / ❌ Serveur web ne peut pas sortir sur Internet. /
> ❌ Accès à Facebook/YouTube bloqués pendant les heures de travail. /
> ❌ Accès à sites pour adultes bloqué depuis le LAN. /
> ✅ Snort doit détecter une tentative de scan de ports depuis WAN.

---

### ✅ Test 1 — WAN peut accéder à la page web de la DMZ
**Console : Client-WAN**
```bash
curl -v --connect-timeout 3 http://192.168.2.10
```
**Résultat attendu :** `HTTP/1.1 200 OK` + page HTML "Welcome to nginx!"

---

### ❌ Test 2 — WAN ne peut pas ping ou accéder au LAN
**Console : Client-WAN**
```bash
ping -c 3 192.168.3.10
```
**Résultat attendu :** `3 packets transmitted, 0 received, 100% packet loss`

---

### ✅ Test 3 — LAN peut accéder à Internet et à la DMZ
**Console : Client-LAN**
```bash
ping -c 3 192.168.1.10
```
**Résultat attendu (accès Internet/WAN) :** `0% packet loss`

```bash
curl -v --connect-timeout 3 http://192.168.2.10
```
**Résultat attendu (accès DMZ) :** `HTTP/1.1 200 OK` (avec en-têtes `Via: squid`, preuve du passage par le proxy)

---

### ❌ Test 4 — Serveur web ne peut pas sortir sur Internet
**Console : Serveur-Web**
```bash
ping -c 3 192.168.1.10
```
**Résultat attendu :** `100% packet loss` (sortie vers le WAN bloquée)

```bash
ping -c 3 192.168.3.10
```
**Résultat attendu (bonus, non explicitement demandé mais cohérent) :** `100% packet loss` (sortie vers le LAN bloquée aussi)

---

### ❌ Test 5 — Accès à Facebook/YouTube bloqué pendant les heures de travail
**Console : Client-LAN**
```bash
curl -v --connect-timeout 3 http://www.facebook.com
```
**Résultat attendu SI test fait entre 8h-12h ou 14h-18h :** page `ERR_ACCESS_DENIED` (Squid)
**Si hors de ces horaires :** `HTTP 200 OK` — comportement normal, voir procédure ci-dessous pour forcer le test à toute heure.

---

### ❌ Test 6 — Accès à sites pour adultes bloqué depuis le LAN
**Console : Client-LAN**
```bash
curl -v --connect-timeout 3 http://www.playboy.com
```
**Résultat attendu :** page `ERR_ACCESS_DENIED` (Squid), à n'importe quelle heure

---

### ✅ Test 7 — Snort doit détecter une tentative de scan de ports depuis WAN
**Console : Client-WAN** (simulation du scan)
```bash
for port in 20 21 22 23 25 80 443 8080; do
  timeout 1 bash -c "echo > /dev/tcp/192.168.2.10/$port" 2>&1
done
```
**Console : Firewall-3if-1** (vérification de l'alerte)
```bash
cat /var/log/snort/alert
```
**Résultat attendu :** une ligne du type
```
[**] [1:1000001:1] Possible scan de ports detecte [**] {TCP} 192.168.1.10:xxxxx -> 192.168.2.10:xx
```

---

### Bonus — Limitation de bande passante (500 Ko/s, exigence "Services et Comportements Attendus")
**Console : Client-LAN**
```bash
curl -o /dev/null http://192.168.2.10/testfile.bin
```
**Résultat attendu :** vitesse `Current` ≈ 450-500 Ko/s

### Preuve complémentaire — logs Squid
**Console : Firewall-3if-1**
```bash
tail -20 /var/log/squid/access.log
```
**Résultat attendu :** lignes montrant les requêtes filtrées avec `ORIGINAL_DST` et le code de résultat

## Pour forcer le test Facebook/YouTube hors des heures de bureau
```bash
nano /etc/squid/squid.conf
# remplace temporairement : time MTWHF 08:00-12:00  →  time MTWHF 00:00-23:59
squid -k reconfigure
#  remet les vraies heures après le test, puis squid -k reconfigure à nouveau
```
