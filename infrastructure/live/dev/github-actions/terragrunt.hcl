include "root" {
  path = find_in_parent_folders("root.hcl")
}

# An operator manages CI's own permissions; the CI deployment role cannot edit them.
terraform {
  source = "${get_repo_root()}/infrastructure/modules/github-actions"
}

# The API is initially bootstrapped by an operator so CI can use an exact API ARN.
dependency "lambda" {
  config_path = "../lambda"
}

inputs = {
  api_gateway_id = dependency.lambda.outputs.api_gateway_id
}
