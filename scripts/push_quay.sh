#!/bin/sh -ex
export PROJECT_NAME=web-lambdas-terraform
# docker tag ${PROJECT_NAME} quay.io/nyulibraries/${PROJECT_NAME}:${CIRCLE_BRANCH//\//_}
# docker tag ${PROJECT_NAME} quay.io/nyulibraries/${PROJECT_NAME}:${CIRCLE_BRANCH//\//_}-${CIRCLE_SHA1}
# docker tag ${PROJECT_NAME} quay.io/nyulibraries/${PROJECT_NAME}:latest
docker push quay.io/nyulibraries/${PROJECT_NAME}:${CIRCLE_BRANCH//\//_}
docker push quay.io/nyulibraries/${PROJECT_NAME}:${CIRCLE_BRANCH//\//_}-${CIRCLE_SHA1}
docker push quay.io/nyulibraries/${PROJECT_NAME}:latest