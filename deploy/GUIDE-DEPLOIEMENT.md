# Guide de déploiement : Juice Shop sur AWS (atelier agents AWS)

Ce guide déploie Juice Shop avec Terraform : ALB publique (HTTPS, certificat ACM public), ECS Fargate dans des subnets privés, EFS, ECR, alias Route 53. L'application est volontairement vulnérable et sert de cible de test. Détruis-la à la fin de l'atelier.

Tous les chemins sont relatifs à `juice-shop/deploy/terraform/`.

## 1. Prérequis

| Outil | Version | Vérification |
|---|---|---|
| AWS CLI | v2 | `aws --version` |
| Terraform | >= 1.10 (verrouillage S3 natif) | `terraform version` |
| Docker Engine | démon démarré, API accessible à ton utilisateur | `docker version` |

Accès nécessaires :
- le portail SSO de l'atelier (section 2) ;
- la zone Route 53 publique `frontiers.ocbawspractice.com` dans le compte cible ;
- un accès Internet sortant depuis les conteneurs de build (section 4).

### Prérequis Docker (important : Terraform construit l'image)

Terraform n'appelle pas la commande `docker build`. Le provider `kreuzwerker/docker` parle directement à l'API du démon Docker, puis pousse l'image dans ECR. Conséquences :

1. **Un démon Docker doit tourner sur la machine qui lance Terraform.** Il n'y a pas de repli : sans démon, `terraform apply` échoue à la construction.
2. **Ton utilisateur doit pouvoir accéder au socket Docker.** Sous Linux, soit il appartient au groupe `docker` (`id -nG`, vérifie la présence de `docker`), soit tu lances Terraform avec les droits adéquats. Test : `docker ps` doit répondre sans `sudo`.
3. **Le provider utilise le contexte Docker par défaut** (`unix:///var/run/docker.sock`). Si ton démon est ailleurs (Docker Desktop, Colima, Rancher Desktop, hôte distant), vérifie `docker context ls` et exporte `DOCKER_HOST` ou `DOCKER_CONTEXT` avant de lancer Terraform. Le provider les lit.
4. **Si Docker utilise containerd pour stocker les images, le build peut échouer.** La doc du provider indique que le bloc `build` « nécessite que l'option *Use containerd for pulling and storing images* soit désactivée ». Sur Docker Desktop : *Settings > General*, décoche cette option. Sur Docker Engine, vérifie `docker info | grep "Storage Driver"` : `overlay2` convient. Une valeur contenant `containerd` est le cas à risque.
5. **Ressources** : le build compile le frontend Angular. Prévois environ 4 Go de RAM libre pour Docker et plusieurs Go d'espace disque. Sous Docker Desktop ou WSL, vérifie les limites mémoire allouées. Le délai de build par défaut du provider est de 20 minutes.
6. **Architecture** : l'image est construite pour `linux/amd64` (tâche Fargate X86_64). Sur un Mac Apple Silicon ou une machine ARM, le build passe par l'émulation et il est nettement plus lent. Le démon doit supporter cette plateforme (`docker buildx ls` doit lister `linux/amd64`).
7. **Pas de login ECR manuel** : Terraform récupère un jeton ECR temporaire et s'authentifie tout seul. Ne lance pas `docker login` pour ça.

Vérification rapide avant de commencer :

```bash
docker version                                  # client et serveur doivent répondre
docker info | grep -E "Storage Driver"          # attendu : overlay2 (pas containerd)
docker buildx ls                                # doit lister linux/amd64
docker run --rm hello-world                     # le démon peut tirer et lancer une image
```

## 2. Configurer la session SSO et le profil AWS

Paramètres de l'atelier :

| Élément | Valeur |
|---|---|
| URL du portail | `https://obsecamobs.awsapps.com/start` |
| Compte | `OCB0000000_SandBox-FrontierAgents-1` |
| Account ID | `143480595386` |
| Rôle | `SupportLevel4` |
| Nom de profil proposé | `sandbox-frontieragents-1` |

Ce nom de profil est celui attendu par `juice-shop.tfvars` (`aws_profile`) et `backend.hcl` (`profile`). Si tu en choisis un autre, modifie ces deux fichiers.

### Option A : assistant interactif

```bash
aws configure sso
```

| Question | Réponse |
|---|---|
| SSO session name | `obsecamobs` |
| SSO start URL | `https://obsecamobs.awsapps.com/start` |
| SSO region | région d'IAM Identity Center (voir ci-dessous) |
| SSO registration scopes | `sso:account:access` |

Le navigateur s'ouvre pour te connecter. Choisis ensuite le compte `143480595386`, le rôle `SupportLevel4`, puis le nom de profil `sandbox-frontieragents-1`. Région par défaut : `eu-central-1`.

### Option B : édition directe de `~/.aws/config`

Ajoute ces blocs à la fin du fichier, sans remplacer tes sessions existantes :

```ini
[sso-session obsecamobs]
sso_start_url = https://obsecamobs.awsapps.com/start
sso_region = <REGION_DU_PORTAIL>
sso_registration_scopes = sso:account:access

[profile sandbox-frontieragents-1]
sso_session = obsecamobs
sso_account_id = 143480595386
sso_role_name = SupportLevel4
region = eu-central-1
output = json
```

`<REGION_DU_PORTAIL>` est la région où IAM Identity Center est activé. Demande-la aux organisateurs si tu ne la connais pas. Ce n'est pas forcément la région de déploiement.

### Ouvrir la session et vérifier

```bash
aws sso login --profile sandbox-frontieragents-1
aws sts get-caller-identity --profile sandbox-frontieragents-1
```

Le résultat doit afficher `"Account": "143480595386"` et un ARN contenant `SupportLevel4`.

La session SSO expire au bout de quelques heures. Si Terraform renvoie `Token has expired and refresh failed`, relance `aws sso login`.

## 3. Backend Terraform : le state et sa clé

Le state est stocké dans un bucket S3 qui existe déjà. Rien à créer. Les paramètres sont dans `backend.hcl` :

| Paramètre | Valeur |
|---|---|
| `bucket` | `tfstate-143480595386-primary` |
| `region` | `eu-west-3` |
| `key` | `lab/aws-security-agent/juice-shop/terraform.tfstate` |
| `profile` | `sandbox-frontieragents-1` |

Vérifie l'accès (optionnel) :

```bash
aws s3 ls s3://tfstate-143480595386-primary/lab/aws-security-agent/ --profile sandbox-frontieragents-1
```

### Déployer une autre instance : change la `key`

La `key` identifie le state. **Deux déploiements qui partagent la même `key` partagent le même state** : le second `apply` modifierait, voire détruirait, l'infrastructure du premier. Pour une autre instance (autre participant, autre environnement), utilise une `key` unique **et** des noms de ressources distincts.

À modifier pour une seconde instance :

| Fichier | Variable | Pourquoi |
|---|---|---|
| `backend.hcl` | `key` | state séparé, par exemple `lab/aws-security-agent/juice-shop-02/terraform.tfstate` |
| `juice-shop.tfvars` | `alb_alias_name` | l'alias DNS doit être unique dans la zone, par exemple `juice-shop-02` |
| `juice-shop.tfvars` | `environment` ou `project_name` | les noms de ressources (ALB, ECS, ECR, security groups) sont dérivés de `project_name-environment`. Ils doivent être uniques dans le compte et la région |
| `juice-shop.tfvars` | `vpc_cidr` | si les deux instances doivent être appairées ou ne pas se chevaucher |

Méthode sans toucher aux fichiers versionnés :

```bash
# 1. changer la clé à l'init, sans modifier backend.hcl
terraform init -backend-config=backend.hcl \
  -backend-config="key=lab/aws-security-agent/juice-shop-02/terraform.tfstate" \
  -reconfigure

# 2. surcharger les variables à la volée
terraform plan -var-file=juice-shop.tfvars \
  -var="alb_alias_name=juice-shop-02" \
  -var="environment=lab02" \
  -out=tfplan
terraform apply tfplan
```

`-reconfigure` est nécessaire quand tu changes de `key` dans un répertoire déjà initialisé : il réinitialise le backend sans migrer le state de l'instance précédente. Sans lui, Terraform te propose de **migrer** l'ancien state vers la nouvelle clé : réponds non.

Piège fréquent : un répertoire de travail ne peut parler qu'à un seul state à la fois. Pour gérer deux instances en parallèle, utilise deux copies du dépôt, ou ré-initialise (`-reconfigure`) à chaque changement d'instance. Vérifie toujours la clé active avant un `apply` ou un `destroy` :

```bash
cat .terraform/terraform.tfstate | grep '"key"'
```

Le jeton de vérification AWS Security Agent (section 7) est un fichier du dépôt. Pour deux instances distinctes avec des jetons distincts, utilise deux copies du dépôt, ou liste les deux jetons dans le même tableau `tokens`.

## 4. Proxy : le cas qui diffère d'un utilisateur à l'autre

### Pourquoi le proxy compte

Le build de l'image exécute `npm install` dans un conteneur. Ce conteneur doit joindre Internet (`registry.npmjs.org`). Selon ton réseau :

- **Réseau d'entreprise avec proxy** : les conteneurs ne sortent pas directement, ils doivent passer par le proxy.
- **Réseau avec accès direct** : aucun proxy n'est nécessaire.

Le détail qui piège : le CLI `docker build` injecte tout seul le proxy défini dans `~/.docker/config.json`. Le provider Terraform appelle l'API Docker directement et **n'applique pas ce réglage**. Un build manuel peut donc réussir et le build Terraform échouer. C'est pour cela que ce Terraform passe le proxy explicitement, en build-args.

Test réalisé sur la machine de référence : un conteneur lancé sans proxy expire (`UND_ERR_CONNECT_TIMEOUT`), alors que le même conteneur avec le proxy accède bien à `registry.npmjs.org`. À l'inverse, l'hôte lui-même accédait directement à Internet. Un test depuis l'hôte seul ne prouve donc rien sur les conteneurs.

### Variables concernées (`juice-shop.tfvars`)

| Variable | Rôle | Défaut dans le fichier |
|---|---|---|
| `docker_build_proxy_enabled` | active ou désactive le proxy pendant le build | `true` |
| `docker_build_proxy` | URL du proxy, format `http://hôte:port` | `http://10.242.191.81:80` |
| `docker_build_no_proxy` | hôtes qui contournent le proxy | `localhost,127.0.0.1` |

**La valeur par défaut est celle d'une machine de référence. Elle ne sera pas bonne pour toi** si ton proxy est différent. Détermine ta propre valeur avec les étapes ci-dessous.

### Déterminer ton proxy actuel

Teste dans cet ordre. Arrête-toi à la première commande qui retourne une valeur.

```bash
# 1. Variables d'environnement du shell (cas le plus courant)
env | grep -i -E '^(http|https|no|all)_proxy='

# 2. Configuration du CLI Docker (utilisée par docker build, pas par Terraform)
python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.docker/config.json'))).get('proxies',{}))"

# 3. Configuration du démon Docker (utilisée pour tirer les images de base)
docker info | grep -i proxy

# 4. Autres outils déjà configurés sur ta machine
git config --global --get http.proxy
npm config get https-proxy
cat /etc/apt/apt.conf.d/*proxy* 2>/dev/null
```

Interprétation :

| Résultat | Que faire |
|---|---|
| L'étape 1 ou 2 donne une URL | reporte-la dans `docker_build_proxy` |
| Seule l'étape 3 donne une valeur | c'est le proxy du démon : tente-la aussi pour le build |
| Rien nulle part | tu n'as probablement pas de proxy : passe à la vérification ci-dessous |
| Ton navigateur utilise un fichier PAC ou `proxy.pac` | demande l'adresse du proxy à ton équipe réseau : le build ne lit pas les fichiers PAC |

Si ton proxy demande une authentification, l'URL est `http://utilisateur:motdepasse@hôte:port`. **Ne commite pas cette valeur** : passe-la en ligne de commande avec `-var` ou via `TF_VAR_docker_build_proxy`, et garde `juice-shop.tfvars` sans identifiants.

### Vérifier que la valeur fonctionne, depuis un conteneur

Ne teste pas depuis l'hôte : le résultat n'est pas représentatif. Teste depuis un conteneur, avec l'image utilisée par le build.

Sans proxy (le cas où tu penses ne pas en avoir besoin) :

```bash
docker run --rm node:24 node -e "fetch('https://registry.npmjs.org/').then(r=>console.log('HTTP',r.status)).catch(e=>console.log('KO',e.cause&&e.cause.code||e.message))"
```

- `HTTP 200` : accès direct. Mets `docker_build_proxy_enabled = false`.
- `KO UND_ERR_CONNECT_TIMEOUT` (ou `ETIMEDOUT`, `ENOTFOUND`) : il te faut un proxy, passe au test suivant.

Avec ton proxy candidat :

```bash
docker run --rm -e https_proxy="http://HOTE:PORT" node:24 \
  sh -c 'curl -sS -m 15 -o /dev/null -w "HTTP %{http_code}\n" https://registry.npmjs.org/'
```

`HTTP 200` : la valeur est bonne, reporte-la dans `docker_build_proxy`.

### Désactiver ou modifier le proxy

Les trois façons, de la plus simple à la plus permanente :

```bash
# Désactiver ponctuellement, sans modifier de fichier
terraform apply -var-file=juice-shop.tfvars -var="docker_build_proxy_enabled=false"

# Changer l'adresse ponctuellement
terraform apply -var-file=juice-shop.tfvars -var="docker_build_proxy=http://mon-proxy:3128"

# Via variable d'environnement (utile pour un proxy authentifié)
export TF_VAR_docker_build_proxy="http://user:pass@mon-proxy:3128"
terraform apply -var-file=juice-shop.tfvars
```

Pour rendre le changement permanent, modifie `juice-shop.tfvars` :

```hcl
docker_build_proxy_enabled = false                    # accès direct
# ou
docker_build_proxy_enabled = true
docker_build_proxy         = "http://mon-proxy:3128"
docker_build_no_proxy      = "localhost,127.0.0.1,.interne.exemple"
```

Quand `docker_build_proxy_enabled = false`, les valeurs de `docker_build_proxy` et `docker_build_no_proxy` sont ignorées, mais elles doivent rester définies dans le fichier.

Après un changement de proxy, relance un build forcé si l'image existe déjà :

```bash
terraform apply -var-file=juice-shop.tfvars -replace=docker_image.app
```

### Autres proxys éventuels

- **Terraform lui-même** (téléchargement des providers, appels AWS) utilise les variables d'environnement `HTTPS_PROXY` et `NO_PROXY` de ton shell. Elles sont indépendantes des variables Terraform ci-dessus.
- **L'AWS CLI** les utilise aussi. Si l'accès aux API AWS ne passe pas, vérifie que `*.amazonaws.com` n'est pas dans `NO_PROXY` par erreur.
- **Le démon Docker** a son propre proxy pour tirer l'image de base `node:24`. Il se configure côté démon (`/etc/systemd/system/docker.service.d/` ou Docker Desktop > Settings > Resources > Proxies), pas dans Terraform.

## 5. Vérifier les paramètres de déploiement

Ouvre `juice-shop.tfvars` et contrôle :

| Variable | Valeur par défaut | À adapter si |
|---|---|---|
| `aws_profile` | `sandbox-frontieragents-1` | tu as choisi un autre nom de profil |
| `aws_region` / `availability_zones` | `eu-central-1` / `eu-central-1a`, `eu-central-1b` | tu changes de région (les 2 AZ doivent en faire partie) |
| `vpc_cidr` | `10.20.0.0/16` | chevauchement avec un autre VPC |
| `alb_alias_name` | `juice-shop-01` | autre instance ou autre participant (section 3) |
| `allowed_ingress_cidrs` | `0.0.0.0/0` | tu veux limiter l'accès (voir ci-dessous) |
| `docker_build_proxy_enabled` et associées | `true` | voir section 4 |

L'URL finale est `https://<alb_alias_name>.frontiers.ocbawspractice.com`.

Avertissement : l'application contient des vulnérabilités volontaires. Garde `0.0.0.0/0` seulement si le test AWS Security Agent l'exige (il doit pouvoir joindre l'ALB), et détruis l'environnement ensuite.

## 6. Déployer

```bash
cd juice-shop/deploy/terraform

aws sso login --profile sandbox-frontieragents-1

terraform init -backend-config=backend.hcl
terraform plan  -var-file=juice-shop.tfvars -out=tfplan
terraform apply tfplan
```

`terraform init` récupère les providers (`aws`, `kreuzwerker/docker`) et se connecte au bucket S3. Si un state local `terraform.tfstate` existe déjà dans le répertoire, Terraform propose de le migrer vers S3 : réponds `yes` seulement si c'est bien le state de cette instance.

Durées indicatives :
- build de l'image (compilation Angular) : plusieurs minutes, 20 minutes maximum avant expiration ;
- validation du certificat ACM par DNS : quelques minutes ;
- démarrage de la tâche ECS : 1 à 3 minutes.

Résultat et vérification :

```bash
terraform output app_url_https
curl -I https://juice-shop-01.frontiers.ocbawspractice.com
```

Le certificat est public (ACM) : `curl` n'a pas besoin de `-k`.

## 7. Domaine de vérification AWS Security Agent

Pour prouver la propriété du domaine par HTTP, l'application sert ce fichier :

```
juice-shop/.well-known/aws/securityagent-domain-verification.json
```

Contenu à renseigner :

```json
{
  "tokens": ["<JETON_FOURNI_PAR_AWS_SECURITY_AGENT>"]
}
```

Étapes :
1. Dans la console AWS Security Agent, ajoute le domaine cible et copie le jeton HTTP.
2. Remplace la valeur factice `REPLACE_WITH_SECURITY_AGENT_TOKEN` dans le fichier. Plusieurs jetons sont possibles dans le tableau si le domaine est dans plusieurs Agent Spaces.
3. Relance `terraform apply -var-file=juice-shop.tfvars`. Terraform reconstruit l'image, la pousse dans ECR et redéploie la tâche.
4. Contrôle :
   ```bash
   curl https://juice-shop-01.frontiers.ocbawspractice.com/.well-known/aws/securityagent-domain-verification.json
   ```
5. Dans la console, sélectionne le domaine et choisis **Verify**.

## 8. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| `Token has expired and refresh failed` | session SSO expirée | `aws sso login --profile sandbox-frontieragents-1` |
| `Cannot connect to the Docker daemon` | démon arrêté ou socket inaccessible | démarrer Docker, vérifier le groupe `docker`, `DOCKER_HOST` |
| `permission denied ... docker.sock` | utilisateur hors du groupe `docker` | ajouter l'utilisateur au groupe, puis rouvrir la session |
| Build bloqué ou en échec à `npm install -g typescript` | conteneur sans accès Internet | section 4 : activer ou corriger le proxy |
| Build qui réussit à la main mais échoue dans Terraform | le provider n'applique pas le proxy du CLI Docker | section 4 : renseigner `docker_build_proxy` |
| Build tué (`exit code 137`) ou très lent | mémoire insuffisante pour Docker | augmenter la mémoire allouée (Docker Desktop, WSL) |
| Erreur de build liée à containerd | stockage d'images containerd activé | désactiver *Use containerd for pulling and storing images* |
| `exec format error` ou build très lent | architecture ARM, émulation amd64 | prévoir plus de temps, ou construire sur une machine amd64 |
| `no matching Route 53 Hosted Zone` | zone absente du compte | vérifier `route53_zone_name`, zone publique du compte `143480595386` |
| Validation du certificat qui n'aboutit pas | zone non délégable publiquement | vérifier la délégation NS de la zone |
| `Error acquiring the state lock` | un autre `apply` en cours ou interrompu | attendre, ou `terraform force-unlock <ID>` si tu es sûr |
| `AccessDenied` sur le bucket S3 | mauvais profil ou mauvaise région dans `backend.hcl` | vérifier `profile` et `region` |
| Ressources d'une autre instance modifiées | `key` partagée entre deux déploiements | section 3 : `key` unique et `-reconfigure` |
| `Invalid security group description` | caractère interdit (apostrophe, accent) | n'utiliser que `a-zA-Z0-9 . _-:/()#,@[]+=&;{}!$*` |

## 9. Nettoyage

Détruis tout en fin d'atelier, **avec la bonne `key` active** (section 3) :

```bash
cat .terraform/terraform.tfstate | grep '"key"'    # vérifier l'instance ciblée
terraform destroy -var-file=juice-shop.tfvars
```

Cela supprime le VPC, l'ALB, ECS, EFS, ECR (avec ses images), le certificat et l'alias DNS. Le bucket de state n'est pas géré par ce Terraform et reste en place.
