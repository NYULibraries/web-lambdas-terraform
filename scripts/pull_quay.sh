#!/bin/sh -ex
export PROJECT_NAME=web-lambdas-terraform
docker pull quay.io/nyulibraries/${PROJECT_NAME}:${CIRCLE_BRANCH//\//_} || docker pull quay.io/nyulibraries/${PROJECT_NAME}:latest