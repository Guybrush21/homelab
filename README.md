# elaine Home Lab

This is my personal docker compose repository for self-hosted service running in my homelab server. 

## The guide I followed

<https://blog.gurucomputing.com.au/doing-more-with-docker/designing-our-workspace/>

That is a really masterpiece. Just saying.

## Server
As per possible all services are containered and managed with *docker compose*.

Server is an AMD Ryzen 3 3200G with Arch Linux installed, with 8GB of ram (5 ram + 3 swap/zram). Server hostname is **elaine**

Drives are configured as follow:

1. 250GB SSD brtfs formatted used for   
   1. /root
   2. /home/vol-docker
2. 2x2Tib HDD in Raid 1 using mdadm used for (called md/murray)   
   1. /home

## Repository GitOps
<https://github.com/Guybrush21/homelab>

### Repo Structure

* git
  * deluge
    * container-data/
    * docker-compose.yaml
    * .env (*optional)*
  * nginx-proxy-manager
    * container-data/
    * …
  * …

All docker compose file are organized in single folder. There is a special folder called **backup** which contain the systemd service and timer used for backuping all this structure. This way the backup is done both for the .yaml files and the container-data files which is where the volumes are mounted.

Volumes are (generally) all mounted in corresponding folder under ./container-data/whatever which is then gitignored. While this comes in handy for the backup, some images explicitally require named volumes. Probably a better approach is to use named volumes for everything and add a backup of the /

## Backup

Backup is done with [restic](https://restic.net/) invoked by a systemd unit. Right now I’m only backuping from the SSD to the RAID1 disk. This is enough for me even if both disk are located in the same pc (meh…). Restic have many options for REST\Cloud repository which, one day, I will try.

TODO:

- [ ] backup of named volume not created in container-data

## Secrets

By now the .gitignore is configured to ignore all **.env* files. This allows to safely use the built-in docker compose environment configurations while not deploying it to my public GitHub repository. 


## elaine.pw and the magic world of internet domains and dns

I’ve bought the elaine.pw domain in [namecheap](https://www.namecheap.com/) in honor of governor Elaine from Monkey Island.

With some black magic about DNS I’ve managed to use it in [Cloudflare](https://www.cloudflare.com). Cloudflare is resolving to my homelab server thanks to the ddclient container. It’s configuration is pretty simple.

## Reverse Proxy

Reverse proxy is done with the great [nginx-proxy-manger](https://nginxproxymanager.com/) which is just a nice ui for nginx with [Let’s Encrypt](https://letsencrypt.org/) utilities built-in.

Basically the only ports forwared from my router to the homelab are the 80 and 443. These are exposed by the nginx-proxy-manager container that then will internally forward incoming connections to the proper container using subdomain like homer.elaine.pw or appsmith.elaine.pw etc. Inside the nginx-proxy-manager you can create a SSL certificate that then will be used for all the *.elaine.pw.

In order to the reverse proxy to work all the containers who should be be exposed need to be on the same network. This is achieved easily in two steps:

1. create an external network, named *reverseproxy* here, that we can refer to

   `docker network create reverseproxy`
2. refer to *reverseproxy* in all the containers created with compose

```yaml
volumes: - ./container-data/mysql:/var/lib/mysql

networks:
- nginx-proxy-manager-nw

networks:
  reverseproxy:
  external: true 
  nginx-proxy-manager-nw:
```

That’s it.

## Networking

Docker Compose built in provide network for all service defined in same compose file. Some defined services are cross-used internally by one or more applications: postgresql or nginx-proxy-manager. This is achieved using docker’s external networks. 

`docker network create network-name`

and then in compose yaml 

```yaml
networks:
- nginx-proxy-manager-nw

networks:
  reverseproxy:
  external: true 
  nginx-proxy-manager-nw:
```
