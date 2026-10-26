include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/streamlit-access"
}

dependency "lambda" { config_path = "../lambda" }

inputs = {
  api_execution_arn = dependency.lambda.outputs.api_execution_arn
}
