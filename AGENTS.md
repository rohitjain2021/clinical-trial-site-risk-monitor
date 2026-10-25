# Project Development Rules

- Follow KISS (Keep It Simple, Stupid). Implement the smallest clear solution for the requested task.
- Read the README's Things to Do checklist before choosing new implementation work. Do not implement unrelated checklist items automatically.
- Prefer straightforward functions and standard-library tools. Add abstractions, dependencies, services, or configuration only when the current requirement justifies them.
- Every function must have a comment or docstring explaining what it does, how it works, and why it is used in this project.
- Preserve the documented API contract and input validation when refactoring. Run relevant existing tests after behavior-affecting edits.
- Preserve authentication, least-privilege IAM, permissions boundaries, secret scanning, and credential protection. Simplicity is not a reason to remove required security controls.
- All AWS resource creation and configuration changes must use Terraform and Terragrunt.
- Keep deployed identifiers in ignored local configuration or encrypted CI secrets. Never commit credentials, real trial data, Terraform state, or saved plans.
- Distinguish implemented behavior from planned features in code examples and documentation.
- Build and test risk rules and the service locally before provisioning their EKS infrastructure.
