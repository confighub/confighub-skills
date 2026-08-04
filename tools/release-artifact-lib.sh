#!/usr/bin/env bash

release_source_paths() {
  local artifact_root=$1
  (
    cd "$artifact_root" || exit 1
    find . -type f \
      ! -path './.git/*' \
      ! -path './compatibility/release-artifact-manifest.v1.json' \
      -print |
      sed 's|^./||' |
      LC_ALL=C sort
  )
}

release_package_paths() {
  local artifact_root=$1
  (
    cd "$artifact_root" || exit 1
    find .claude-plugin commands compatibility hooks references skills -type f \
      ! -path 'compatibility/release-artifact-manifest.v1.json' \
      -print |
      LC_ALL=C sort
  )
}

release_canonical_lines() {
  local artifact_root=$1
  local paths_file=$2
  local output_file=$3
  : >"$output_file"
  while IFS= read -r path; do
    test -n "$path" || continue
    case "$path" in
      *$'\n'*) return 2 ;;
    esac
    local digest
    local mode
    digest=$(shasum -a 256 "$artifact_root/$path" | awk '{print $1}')
    mode=100644
    test -x "$artifact_root/$path" && mode=100755
    printf '%s %s  %s\n' "$mode" "$digest" "$path" >>"$output_file"
  done <"$paths_file"
}

release_file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}
