terraform {
  backend "s3" {
    bucket       = "vulntrack-tfstate-825990809758"
    key          = "eks/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
    profile      = "vulntrack-terraform"
  }
}