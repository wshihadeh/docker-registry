# registry-cleanup
Script to cleanup docker registry

## Default Config

```bash
: ${REGISTRY_URL:=http://127.0.0.1:5000}
: ${REGISTRY_DIR:=./data}
: ${MAX_AGE_SECONDS:=$((30 * 24 * 3600))} # 30 days
: ${DOCKER_REGISTRY_NAME:=registry_web}
: ${DOCKER_REGISTRY_CONFIG:=/etc/docker/registry/config.yml}
: ${DRY_RUN:=false}

EXCLUDE_TAGS="^(\*|master|develop|latest|stable|(v|[0-9]\.)[0-9]+(\.[0-9]+)*)$"
```

## Usage

- Dry-run mode

```
  CURL_INSECURE=true DRY_RUN=true ./registry_cleanup.sh
```

- Execute cleanup

```
  CURL_INSECURE=true DRY_RUN=true ./registry_cleanup.sh
```
