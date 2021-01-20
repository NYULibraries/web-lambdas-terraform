#!/bin/sh
set -e

terraform init -backend-config=config/${BACKEND_CONFIG}

exec "$@"