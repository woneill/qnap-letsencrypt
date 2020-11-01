#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LEGO_BIN=${SCRIPT_DIR}/lego

# shellcheck source=shflags
. "${SCRIPT_DIR}"/shflags

# define a 'name' command-line string flag
DEFINE_string 'LEGOVERSION' '3.8.0' 'Lego version to install' 'l'
DEFINE_string 'EMAIL' '' 'email address' 'e'
DEFINE_string 'DOMAIN' '' 'domain for certificate' 'd'
DEFINE_string 'GANDIV5_API_KEY' '' 'API key for GANDIV5' 'a'
DEFINE_string 'GANDIV5_API_KEY_FILE' "${SCRIPT_DIR}/.gandiv5_api_key" 'API key file for GANDIV5' 'f'
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

create_api_key_file() {
    echo "Storing API key as ${FLAGS_GANDIV5_API_KEY_FILE}"
    echo "${FLAGS_GANDIV5_API_KEY}" > "${FLAGS_GANDIV5_API_KEY_FILE}"
    chmod 600 "${FLAGS_GANDIV5_API_KEY_FILE}"
}

if [ -z "${FLAGS_GANDIV5_API_KEY}" ]; then
    if ! [ -f "${FLAGS_GANDIV5_API_KEY_FILE}" ]; then
        die "GANDIV5_API_KEY is unset"
    fi
else
    if [ -f "${FLAGS_GANDIV5_API_KEY_FILE}" ]; then
        if [ "$(cat "${FLAGS_GANDIV5_API_KEY_FILE}")" != "${FLAGS_GANDIV5_API_KEY}" ]; then
            echo "API key doesn't match what is already stored!"
            create_api_key_file
        fi
    else
        create_api_key_file
    fi
fi

if ! { [ -x "${LEGO_BIN}" ] && [ "$(${LEGO_BIN} --version)" == "lego version ${FLAGS_LEGOVERSION} linux/amd64" ]; }; then
    download_url="https://github.com/go-acme/lego/releases/download/v${FLAGS_LEGOVERSION}/lego_v${FLAGS_LEGOVERSION}_linux_amd64.tar.gz"
    curl -sSL "$download_url" | tar zxf - lego
    echo "Downloaded lego v${FLAGS_LEGOVERSION}"
fi

if [ "${FLAGS_testing}" -eq ${FLAGS_TRUE} ]; then
    SERVER_FLAGS='--server=https://acme-staging-v02.api.letsencrypt.org/directory'
fi


GANDIV5_API_KEY_FILE="${FLAGS_GANDIV5_API_KEY_FILE}" ${LEGO_BIN} ${SERVER_FLAGS} --email="${FLAGS_EMAIL}" --domains="${FLAGS_DOMAIN}" --dns="gandiv5" --dns.resolvers="8.8.8.8" --pem run --run-hook="${SCRIPT_DIR}/deploy_hook.sh"

cat <<EOF > "${SCRIPT_DIR}"/renew_certificate.sh
GANDIV5_API_KEY_FILE="${FLAGS_GANDIV5_API_KEY_FILE}" ${LEGO_BIN} ${SERVER_FLAGS} --email="${FLAGS_EMAIL}" --domains="${FLAGS_DOMAIN}" --dns="gandiv5" --dns.resolvers="8.8.8.8" --pem renew --days 45 --renew-hook="${SCRIPT_DIR}/deploy_hook.sh"
EOF
chmod a+x "${SCRIPT_DIR}"/renew_certificate.sh

cat <<EOF >> /etc/config/crontab
30 3 * * * ${SCRIPT_DIR}/renew_certificate.sh >> ${SCRIPT_DIR}/renew_certificate.log 2>&1
EOF

crontab /etc/config/crontab
/etc/init.d/crond.sh restart
