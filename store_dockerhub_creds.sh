#!/bin/bash

# Store DockerHub credentials in Vault securely
export DOCKER_PASSWORD="@Chinomnso2197"
vault kv put secret/craftista/prod/dockerhub username="8060633493" password="$DOCKER_PASSWORD"
unset DOCKER_PASSWORD

# Verify storage
vault kv get secret/craftista/prod/dockerhub
