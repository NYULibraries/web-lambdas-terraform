#!/bin/sh
set -e

if [[ -z $1 ]]
then
  echo "Cannot run set_env.sh without an argument"
  exit 1
fi

yq -M eval ".$1" deploy.yml | sed -r 's/([A-Za-z_]+): (.*)/export \1=\2/' > .env
source .env

export TF_VAR_environment_variables=$(envsubst < .tf_env_vars)
