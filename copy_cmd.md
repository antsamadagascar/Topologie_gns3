## STEP 1: 
docker ps --format '{{.ID}}\t{{.Names}}'

## STEP 2:

docker cp scripts/setup-firewall.sh {id_containter}:/root/
docker cp scripts/setup-client-wan.sh  {id_containter}:/root/
docker cp scripts/setup-serveur-web.sh  {id_containter}:/root/
docker cp scripts/setup-client-lan.sh  {id_containter}:/root/


## STEP 3
bash /root/setup-firewall.sh      # console Firewall-3if-1
bash /root/setup-client-wan.sh    # console Client-WAN
bash /root/setup-serveur-web.sh   # console Serveur-Web
bash /root/setup-client-lan.sh    # console Client-LAN
