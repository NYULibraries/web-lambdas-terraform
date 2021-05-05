#!/bin/sh
set -e

terraform init -backend-config="bucket=${BACKEND_BUCKET}" \
               -backend-config="key=${BACKEND_KEY}" \
               -backend-config="region=${BACKEND_REGION}" \
               -backend-config="dynamodb_table=${BACKEND_DYNAMODB_TABLE}"
