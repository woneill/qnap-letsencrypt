#!/usr/bin/env bash
set -o errexit

LEGO_CERT_PEM_PATH=$(dirname "$LEGO_CERT_KEY_PATH")/${LEGO_CERT_DOMAIN}.pem

trap error_cleanup ERR

error_cleanup() {
    echo "An error occured. Restoring system state."
    cleanup
}

cleanup() {
    /etc/init.d/stunnel.sh start
    /etc/init.d/Qthttpd.sh start
}

if [ ! -f "${LEGO_CERT_PEM_PATH}" ]; then
    cat "${LEGO_CERT_KEY_PATH}" "${LEGO_CERT_PATH}" > "${LEGO_CERT_PEM_PATH}"
fi

echo "Stopping stunnel and setting new stunnel certificates..."
/etc/init.d/stunnel.sh stop
cat "${LEGO_CERT_PEM_PATH}" > /etc/stunnel/stunnel.pem
if [ -f /etc/stunnel/uca.pem ]; then rm /etc/stunnel/uca.pem; fi

# FTP
cp "$LEGO_CERT_KEY_PATH" /etc/stunnel/backup.key
cp "$LEGO_CERT_PATH" /etc/stunnel/backup.cert
if pidof proftpd > /dev/null; then
    echo "Restarting FTP"
    /etc/init.d/ftp.sh restart || true
fi

echo "Done! Service startup and cleanup will follow now..."

cleanup
