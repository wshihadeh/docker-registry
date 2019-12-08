#!/bin/bash -e
#
# automatically Cleanup old docker images and tags
#

# Configs

: ${REGISTRY_URL:=http://127.0.0.1:5000}
: ${REGISTRY_DIR:=./data}
: ${MAX_AGE_SECONDS:=$((30 * 24 * 3600))} # 30 days
: ${DOCKER_REGISTRY_NAME:=registry_web}
: ${DOCKER_REGISTRY_CONFIG:=/etc/docker/registry/config.yml}
: ${DRY_RUN:=false}

EXCLUDE_TAGS="^(\*|master|develop|latest|stable|(v|[0-9]\.)[0-9]+(\.[0-9]+)*)$"
REPO_DIR=${REGISTRY_DIR}/docker/registry/v2/repositories

# In doubt fall back to dry mode
[[ $DRY_RUN != "false" ]] && DRY_RUN=true


_curl() {
  curl -fsS ${CURL_INSECURE_ARG} "$@"
}

# parse yyyymmddHHMMSS string into unix timestamp
datetime_to_timestamp() {
  echo "$1" | awk 'BEGIN {OFS=""} { print substr($1,0,4), "-", substr($1,5,2), "-", substr($1,7,2), " ", substr($1,9,2), ":", substr($1,11,2), ":", substr($1,13,2) }'
}

run_garbage() {
  echo "Running garbage-collect command ..."
  local dry_run_arg=
  $DRY_RUN && dry_run_arg=--dry-run
  docker exec -i $DOCKER_REGISTRY_NAME /bin/registry garbage-collect $DOCKER_REGISTRY_CONFIG $dry_run_arg > /dev/null
}

remove_old_tags() {
  echo "Start Remove Old Tags ..."
  local repo_path image_path
  TAG_COUNT=0

  for repo_path in $REPO_DIR/*; do
    local repo=$(basename $repo_path)
    echo "Current repo: $repo"

    for image_path in $repo_path/*; do
      local image=$(basename $image_path)
      remove_image_tags "$repo" "$image"
    done
    echo
  done
}

remove_image_tags() {
  local repo=$1
  local image=$2

  echo "- Cleanup image $repo/$image"

  local tag_path
  for tag_path in $REPO_DIR/$repo/$image/_manifests/tags/*; do
    local tag=$(basename $tag_path)

    # Do not clenup execluded tags
    if ! [[ $tag =~ $EXCLUDE_TAGS ]]; then
      # get timestamp from tag folder
      local timestamp=$(date -d @$(stat -c %Y $tag_path) +%Y%m%d%H%M%S)

      # parse yyyymmddHHMMSS string into unix timestamp
      timestamp=$(date -d "$(datetime_to_timestamp "$timestamp")" +%s)
      local now=$(date +%s)

      # check if the tag is old enough to delete
      if ((now - timestamp > $MAX_AGE_SECONDS)); then
        if $DRY_RUN; then
          echo "To be Deleted >>  rm -rf ${tag_path}"
        else
          echo "Deleted: $tag"
          TAG_COUNT=$((TAG_COUNT+1))
          rm -rf ${tag_path}
        fi
      fi
    fi
  done
}

delete_manifests_without_tags(){
  cd ${REPO_DIR}

  local manifests_without_tags=$(
    comm -23 <(
      find . -type f -path "./*/*/_manifests/revisions/sha256/*/link" |
      grep -v "\/signatures\/sha256\/" |
      awk -F/ '{print $(NF-1)}' |
      sort -u
    ) <(
      find . -type f -path './*/*/_manifests/tags/*/current/link' |
      xargs sed 's/^sha256://' |
      sort -u
    )
  )

  CURRENT_COUNT=0
  FAILED_COUNT=0
  TOTAL_COUNT=$(echo ${manifests_without_tags} | wc -w | tr -d ' ')

  if [ ${TOTAL_COUNT} -gt 0 ]; then
    echo -n "Found ${TOTAL_COUNT} manifests. "
    if $DRY_RUN; then
      echo "Run without --dry-run to clean up"
    else
      echo "Starting to clean up"
    fi

    local manifest
    for manifest in ${manifests_without_tags}; do
      local repos=$(
        find . -path "./*/*/_manifests/revisions/sha256/${manifest}/link" |
        sed 's#^./\(.*\)/_manifest.*$#\1#'
      )

      for repo in $repos; do
        if $DRY_RUN; then
          echo "Would have run: _curl -X DELETE ${REGISTRY_URL}/v2/${repo}/manifests/sha256:${manifest} > /dev/null"
        else
          if _curl -X DELETE ${REGISTRY_URL}/v2/${repo}/manifests/sha256:${manifest} > /dev/null; then
            CURRENT_COUNT=$((CURRENT_COUNT+1))
          else
            FAILED_COUNT=$((FAILED_COUNT+1))
          fi
        fi
      done
    done
  else
    echo "No manifests without tags found. Nothing to do."
  fi
}

print_summary(){
  if $DRY_RUN; then
    echo "DRY_RUN over"
  else
    echo "Job done"
    echo "Removed ${TAG_COUNT} tags."
    echo "Removed ${CURRENT_COUNT} of ${TOTAL_COUNT} manifests."

    [ ${FAILED_COUNT} -gt 0 ] && echo "${FAILED_COUNT} manifests failed. Check for curl errors in the output above."

    echo "Disk usage before and after:"
    echo "${DF_BEFORE}"
    echo
    echo "${DF_AFTER}"
  fi
}

start_cleanup(){
  $DRY_RUN && echo "Running in dry-run mode. Will not make any changes"

  #Check registry dir
  if [ ! -d ${REPO_DIR} ]; then
    echo "REPO_DIR doesn't exist. REPO_DIR=${REPO_DIR}"
    exit 1
  fi

  #correct registry url (remove trailing slash)
  REGISTRY_URL=${REGISTRY_URL%/}

  #run curl with --insecure?
  [ "$CURL_INSECURE" == "true" ] && CURL_INSECURE_ARG=--insecure

  #verify registry url
  if ! _curl -m 3 ${REGISTRY_URL}/v2/ > /dev/null; then
    echo "Could not contact registry at ${REGISTRY_URL} - quitting"
    exit 1
  fi

  DF_BEFORE=$(df -Ph)

  remove_old_tags
  delete_manifests_without_tags
  run_garbage

  DF_AFTER=$(df -Ph)
  print_summary
}

start_cleanup