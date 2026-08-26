#!/usr/bin/env bash
# Git wrapper: auto-prepends Conventional Commits type to commit messages
# that lack one. Used in GitHub Actions so commitlint doesn't reject
# agent commits.

REAL_GIT="$(command -v git)"

if [[ "$1" == "commit" ]]; then
  msg=""
  for (( i=1; i<=$#; i++ )); do
    if [[ "${!i}" == "-m" ]]; then
      next=$((i+1))
      msg="${!next}"
      break
    fi
  done

  if [[ -n "$msg" ]] && ! echo "$msg" | grep -qE '^[a-z]+(\(.+\))?:'; then
    msg="fix: $msg"
    new_args=()
    skip_next=false
    for (( i=1; i<=$#; i++ )); do
      if $skip_next; then
        skip_next=false
        continue
      fi
      if [[ "${!i}" == "-m" ]]; then
        new_args+=("-m" "$msg")
        skip_next=true
      else
        new_args+=("${!i}")
      fi
    done
    exec "$REAL_GIT" commit "${new_args[@]}"
  fi
fi

exec "$REAL_GIT" "$@"
