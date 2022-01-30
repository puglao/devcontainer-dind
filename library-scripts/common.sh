#!/bin/bash

set -xeu

GIT_RELEASE_URL="https://github.com/\${repo_name}/releases"
GIT_DOWNLOAD_URL="https://github.com/\${repo_name}/releases/download/\${target_version}"

function common::prerequisite_check() {
  # check if required commands are availabe in system
  command -v curl > /dev/null
  command -v git > /dev/null
  command -v unzip > /dev/null
}

function common::error() {
  echo "$(date "+%Y-%m-%d %T") $*" >&2
}

function common::github::latest_tag() {
  # return latest pattern matching release tag in repo
  repo_name=$1
  tag_pattern=$2
  latest_ver=''
  page=1
  release_url="$(eval printf "${GIT_RELEASE_URL}")"
  while [[ -z "${latest_ver}" ]]
  do
    tag_list="$(curl -sL "${release_url}?page=${page}" \
    | grep -E "href=\"/${repo_name}/releases/tag/")"
    if [[ -z "${tag_list}" ]]; then
      common::error "no release tag match pattern"
      break
    fi
    latest_ver="$(grep -E "href=\"/${repo_name}/releases/tag/${tag_pattern}\"" <<<"${tag_list}" \
    | sed -E "s/^.*(${tag_pattern}).*$/\1/g" \
    | sort -Vr \
    | head -1)"
    ((page++))
  done
  echo "${latest_ver}"
}

function common::github:version_check() {
  # check if specific version is avaiable in repo
  repo_name=$1
  target_version=$2
  status_code="$(curl -o /dev/null -sL -w "%{http_code}\n" "$(eval echo "${GIT_RELEASE_URL}"/tag/"${target_version}")")"
  if [[ "${status_code}" != '200' ]]; then
    common::error "target verion ${target_version} not found in repo ${repo_name}"
    exit 1
  fi
  exit 0
}

function common::github::download_url() {
  # generate release asset download link
  repo_name=$1
  target_version=$2
  download_pattern=$3
  download_url="$(eval printf "${GIT_DOWNLOAD_URL}/${download_pattern}")"
  echo "${download_url}"
}
