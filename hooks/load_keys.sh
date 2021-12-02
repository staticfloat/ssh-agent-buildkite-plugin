#!/bin/bash

set -eou pipefail

# Helper function to kill execution when something goes wrong
function die() {
    echo "ERROR: ${1}" >&2
    if which buildkite-agent >/dev/null 2>/dev/null; then
        # By default, the annotation context is unique to the message
        local CONTEXT=$(echo "${1}" | ${SHASUM})
        if [[ "$#" -gt 1 ]]; then
            CONTEXT="${2}"
        fi
        buildkite-agent annotate --context="${CONTEXT}" --style=error "${1}"
    fi
    exit 1
}

# Check to see if the user has specified where the ssh-agent socket should live
SSH_AGENT_A_FLAG=""
if [[ -v "BUILDKITE_PLUGIN_SSH_AGENT_SOCKET" ]]; then
    # If we're being asked to put an ssh-agent socket somewhere, let's ensure
    # that the directory exists, and that there's no file there
    mkdir -p "$(dirname "${BUILDKITE_PLUGIN_SSH_AGENT_SOCKET}")"
    if [[ -f "${BUILDKITE_PLUGIN_SSH_AGENT_SOCKET}" ]]; then
        die "Requested ssh-agent socket path already exists!"
    fi
    SSH_AGENT_A_FLAG="-a ${BUILDKITE_PLUGIN_SSH_AGENT_SOCKET}"
fi

# Start up ssh-agent
eval "$(ssh-agent ${SSH_AGENT_A_FLAG} -s 2>/dev/null)"

# Load keyfiles off of disk
IDX=0
while [[ -v "BUILDKITE_PLUGIN_SSH_AGENT_KEYFILES_${IDX}" ]]; do
    VARNAME="BUILDKITE_PLUGIN_SSH_AGENT_KEYFILES_${IDX}"
    if [[ -f "${!VARNAME}" ]]; then
        cat "${!VARNAME}" | ssh-add -
    else
        echo "Skipping ${!VARNAME} as it doesn't exist (yet)"
    fi

    IDX=$((${IDX} + 1))
done

# Decode environment variables, and pipe them in through `stdin`
IDX=0
while [[ -v "BUILDKITE_PLUGIN_SSH_AGENT_KEYVARS_${IDX}" ]]; do
    # First, build buildkite plugin variable name
    VARNAME="BUILDKITE_PLUGIN_SSH_AGENT_KEYVARS_${IDX}"
    # Use that to get the actual keyfile variable name
    VARNAME="${!VARNAME}"
    # Then we dereference _again_ to get the actual keyfile contents
    base64 -d <<< "${!VARNAME}" | ssh-add -

    IDX=$((${IDX} + 1))
done

# List all loaded SSH keys
ssh-add -l || true
