#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LEGO_BIN=${SCRIPT_DIR}/lego
LEGO_DIR=${SCRIPT_DIR}/.lego

# shellcheck source=/dev/null
if [ -f "${SCRIPT_DIR}/.env" ]; then
    . "${SCRIPT_DIR}/.env"
fi

# shellcheck source=shflags
. "${SCRIPT_DIR}"/shflags

# define a 'name' command-line string flag
DEFINE_string 'LEGOVERSION' "${LEGOVERSION:-4.12.3}" 'Lego version to install' 'l'
DEFINE_string 'EMAIL' "${EMAIL:-}" 'email address' 'e'
DEFINE_string 'DOMAIN' "${DOMAIN:-}" 'domain for certificate' 'd'
DEFINE_string 'PROVIDER' "${PROVIDER:-digitalocean}" 'LEGO DNS provider' 'p'
DEFINE_string 'AUTH_TOKEN' "${AUTH_TOKEN:-}" "Auth token for ${FLAGS_PROVIDER}" 'a'
DEFINE_string 'AUTH_TOKEN_FILE' "${AUTH_TOKEN_FILE:-${SCRIPT_DIR}/.auth_token}" "Auth token file for ${FLAGS_PROVIDER}" 'f'
DEFINE_boolean 'testing' false 'testing mode' 't'

SERVER_FLAGS=''

# parse the command-line
FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

die() {
    [ $# -gt 0 ] && echo "error: $*" >&2
    exit 1
}

if [ -z "${FLAGS_EMAIL}" ]; then
    die "email is unset"
fi
if [ -z "${FLAGS_DOMAIN}" ]; then
    die "domain is unset"
fi
if [ -z "${FLAGS_AUTH_TOKEN}" ] && [ ! -f "${FLAGS_AUTH_TOKEN_FILE}" ]; then
    die "AUTH_TOKEN is unset"
fi

manage_env_file() {
    cat <<EOF > "${SCRIPT_DIR}/.env"
LEGOVERSION="${FLAGS_LEGOVERSION}"
EMAIL="${FLAGS_EMAIL}"
DOMAIN="${FLAGS_DOMAIN}"
PROVIDER="${FLAGS_PROVIDER}"
AUTH_TOKEN="${FLAGS_AUTH_TOKEN}"
AUTH_TOKEN_FILE="${FLAGS_AUTH_TOKEN_FILE}"
EOF
chmod 600 "${SCRIPT_DIR}/.env"
}

manage_token_file() {
    filename=$1
    token=$2

    if [ -n "$token" ]; then
        if [ "$(cat "${filename}")" != "${token}" ]; then
            echo "Token doesn't match what is already stored in ${filename}. Updating!"
            echo "${token}" > "${filename}"
            chmod 600 "${filename}"
        fi
    fi
}

manage_env_file
manage_token_file "${FLAGS_AUTH_TOKEN_FILE}" "${FLAGS_AUTH_TOKEN}"

if ! { [ -x "${LEGO_BIN}" ] && [ "$(${LEGO_BIN} --version)" == "lego version ${FLAGS_LEGOVERSION} linux/amd64" ]; }; then
    download_url="https://github.com/go-acme/lego/releases/download/v${FLAGS_LEGOVERSION}/lego_v${FLAGS_LEGOVERSION}_linux_amd64.tar.gz"
    if curl -sSL "$download_url" | tar zxf - lego; then
        echo "Downloaded lego v${FLAGS_LEGOVERSION}"
    else
        echo "Failed to download lego v${FLAGS_LEGOVERSION}"
        exit 1
    fi
fi

if [ "${FLAGS_testing}" -eq ${FLAGS_TRUE} ]; then
    SERVER_FLAGS='--server=https://acme-staging-v02.api.letsencrypt.org/directory'
fi

LEGO_BASE_CMD="DO_AUTH_TOKEN_FILE=${FLAGS_AUTH_TOKEN_FILE} ${LEGO_BIN} --path ${LEGO_DIR} ${SERVER_FLAGS} --email=${FLAGS_EMAIL} --domains=${FLAGS_DOMAIN} --dns=${FLAGS_PROVIDER} --dns.resolvers=8.8.8.8"

if [ ! -d "${LEGO_DIR}/certificates" ]; then
    echo "No existing certificate found- creating one"
    ${LEGO_BASE_CMD} --pem run --run-hook="${SCRIPT_DIR}/deploy_hook.sh"
fi

cat <<EOF > "${SCRIPT_DIR}"/renew_certificate.sh
${LEGO_BASE_CMD} --pem renew --days 45 --renew-hook="${SCRIPT_DIR}/deploy_hook.sh"
EOF
chmod a+x "${SCRIPT_DIR}"/renew_certificate.sh


croncmd="${SCRIPT_DIR}/renew_certificate.sh >> ${SCRIPT_DIR}/renew_certificate.log 2>&1"
cronjob="30 3 * * * $croncmd"

tmp=$(mktemp)
( grep -v -F "$croncmd" /etc/config/crontab; echo "$cronjob" ) > "$tmp"

if cmp -s "$tmp" /etc/config/crontab; then
    echo "No changes needed to crontab"
else
    mv "$tmp" /etc/config/crontab
    crontab /etc/config/crontab
    /etc/init.d/crond.sh restart
fi
