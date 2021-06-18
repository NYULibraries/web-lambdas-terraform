#!/bin/sh
set -e

yq -M eval '.'$1'' deploy.yml | xargs -0 > .env
source .env

export TF_VAR_environment_variables=$(envsubst < .tf_env_vars)
