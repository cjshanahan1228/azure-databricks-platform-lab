# TFLint config shared by every root and module (run with `tflint --recursive`
# from the repo root; --config is passed as an absolute path in CI).
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Every variable in this repo has a type; enforce descriptions only on roots
# would be noisy for small modules.
rule "terraform_documented_variables" {
  enabled = false
}
