## STEP 1: 
docker ps --format '{{.ID}}\t{{.Names}}'

## STEP 2:

docker cp setup-firewall.sh d802c9b76b80:/root/
docker cp setup-client-wan.sh 3be8b499dac8:/root/
docker cp setup-serveur-web.sh 213cf2cd740e:/root/
docker cp setup-client-lan.sh ea2926229913:/root/


## STEP 3
bash /root/setup-firewall.sh      # console Firewall-3if-1
bash /root/setup-client-wan.sh    # console Client-WAN
bash /root/setup-serveur-web.sh   # console Serveur-Web
bash /root/setup-client-lan.sh    # console Client-LAN
