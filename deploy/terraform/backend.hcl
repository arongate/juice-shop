# Configuration du backend S3. Non chargé automatiquement :
#   terraform init -backend-config=backend.hcl
# Le bucket doit exister avant l'init (il n'est pas géré par ce Terraform).

bucket  = "tfstate-143480595386-primary"
key     = "lab/aws-security-agent/juice-shop/terraform.tfstate"
region  = "eu-west-3"
profile = "sandbox-frontieragents-1"

encrypt      = true
use_lockfile = true
