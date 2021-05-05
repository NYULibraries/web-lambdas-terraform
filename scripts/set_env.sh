#!/bin/sh
set -e

sed -nr '/'$1':/,$ s/  ([A-Za-z_]+): (.*)/export \1=\2/ p' deploy.yml | xargs -0 > .env
source .env

export TF_VAR_environment_variables=$(envsubst < .tf_env_vars)
