terraform {
  backend "s3" {
    bucket       = "aca-wp-platform-tfstate-459653581653-eu-central-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
