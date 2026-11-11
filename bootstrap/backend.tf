terraform {
  backend "s3" {
    bucket       = "aca-wp-platform-tfstate-459653581653-eu-central-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:eu-central-1:459653581653:key/80ab54b1-69ca-4bfd-a22a-e60a1c8b14ff"
    use_lockfile = true
  }
}
