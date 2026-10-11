#!/usr/bin/env bash
# Configuration checks only. No AWS credentials, plan, or apply required.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

terraform fmt -check -recursive terraform
for script in terraform/live/prod/scripts/*.sh; do
  bash -n "$script"
done

for stack in ecr prod; do
  printf '\nValidating %s\n' "$stack"
  terraform -chdir="terraform/live/$stack" init -backend=false -input=false -lockfile=readonly
  terraform -chdir="terraform/live/$stack" validate -no-color
done
