# Terraform Starter — AWS HA Web Platform
Quick start:
```
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```
After apply, check `alb_dns_name` output.
