# Copy to ignored eks.local.hcl and use your own existing operator and current IP.
locals {
  admin_principal_arn = "arn:aws:iam::123456789012:role/example-operator"
  admin_cidrs         = ["203.0.113.10/32"]
}
