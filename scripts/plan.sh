#!/bin/sh

set -e

if [[ ! -f deploy.yml ]] ; then
    echo 'File is missing: deploy.yml. Exiting...'
    exit
fi

if [[ ! -z $1 ]]
then
  echo "Planning Lambda infrastructure for $1..."
  . set_env.sh $1
  . init_tf_backend.sh
  terraform plan
else
  for app in $(yq -M eval '. | keys' deploy.yml | sed -e 's/^- //' -e 's/-$//')
  do
    echo "Planning Lambda infrastructure for $app..."
    . set_env.sh $app
    . init_tf_backend.sh
    terraform plan
  done
fi

