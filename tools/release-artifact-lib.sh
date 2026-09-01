#!/usr/bin/env bash

# Drop the paths Git ignores. They are machine-local -- a contributor's
# .claude/settings.local.json, editor state, a scratch directory -- so they are no part
# of the artifact and must not reach its digest. Left in, a manifest regenerated on one
# checkout disagrees with the one CI computes over the same commit, and the mismatch
# reports as a file count the reader cannot account for.
#
# Nothing that ships can be dropped by this: `git check-ignore` consults the index, so a
# tracked file is never reported ignored even where a rule would otherwise match it.
#
# Outside a Git worktree -- an unpacked tarball -- there are no ignore rules to read and
# nothing local to strip, so the list passes through. A check-ignore that fails for any
# other reason is an error rather than a pass-through, since passing the list through
# would silently restore the contamination this exists to prevent.
release_drop_ignored_paths() {
  local artifact_root=$1
  local candidates ignored status

  candidates=$(cat)
  test -n "$candidates" || return 0

  if ! git -C "$artifact_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$candidates"
    return 0
  fi

  status=0
  ignored=$(printf '%s\n' "$candidates" | git -C "$artifact_root" check-ignore --stdin) || status=$?
  # 0 = at least one path is ignored, 1 = none is. Anything else is check-ignore failing.
  case "$status" in
    0 | 1) ;;
    *) return 3 ;;
  esac

  if test -z "$ignored"; then
    printf '%s\n' "$candidates"
    return 0
  fi

  LC_ALL=C comm -23 \
    <(printf '%s\n' "$candidates" | LC_ALL=C sort) \
    <(printf '%s\n' "$ignored" | LC_ALL=C sort)
}

release_source_paths() {
  local artifact_root=$1
  (
    cd "$artifact_root" || exit 1
    find . -type f \
      ! -path './.git' \
      ! -path './.git/*' \
      ! -path './compatibility/release-artifact-manifest.v1.json' \
      -print |
      sed 's|^./||'
  ) |
    release_drop_ignored_paths "$artifact_root" |
    LC_ALL=C sort
}

release_package_paths() {
  local artifact_root=$1
  (
    cd "$artifact_root" || exit 1
    find .claude-plugin commands compatibility hooks references skills -type f \
      ! -path 'compatibility/release-artifact-manifest.v1.json' \
      -print
  ) |
    release_drop_ignored_paths "$artifact_root" |
    LC_ALL=C sort
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
