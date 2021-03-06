#!/bin/bash
#
# Copyright (c) 2020, MariaDB Corporation. All rights reserved.
#
INITDBDIR="/es-initdb.d"
#
set -ex
#
function message {
  echo "[Init message]: ${@}"
}
#
function error {
  echo >&2 "[Init ERROR]: ${@}"
}
#
function validate_cfg {
  local RES=0
  local CMD="exec gosu mysql ${@} --verbose --help --log-bin-index=$(mktemp -u)"
  local OUT=$(${CMD}) || RES=${?}
  if [ ${RES} -ne 0 ]; then
    error "Config validation error, please check your configuration!"
    error "Command failed: ${CMD}"
    error "Error output: ${OUT}"
    exit 1
  fi
}
#
function get_cfg_value {
  local conf="${1}"; shift
  "$@" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | grep "^$conf " | awk '{ print $2 }'
}
#
if [[ "${1:0:1}" = '-' ]]; then
  set -- mysqld "${@}"
fi
#
. /etc/IMAGEINFO
message "Preparing MariaDB Enterprise ${ES_VERSION} server..."
#
if [[ -z "${MARIADB_ROOT_PASSWORD}" ]] && [[ -z "${MARIADB_ALLOW_EMPTY_PASSWORD}" ]] && [[ -z "${MARIADB_RANDOM_ROOT_PASSWORD}" ]]; then
  error 'Database will not be initialized because password option is not specified'
  error 'You need to specify one of MARIADB_ROOT_PASSWORD, MARIADB_ALLOW_EMPTY_PASSWORD and MARIADB_RANDOM_ROOT_PASSWORD'
  exit 1
fi
#
if [ "${1}" = "mysqld" ]; then
#
  DATADIR="$(get_cfg_value 'datadir' "$@")"
#
  if [[ ! -d "${DATADIR}/mysql" ]]; then
    message "Initializing database..."
    mysql_install_db --auth-root-socket-user=mysql --datadir="${DATADIR}" --rpm "${@:2}"
    message 'Database initialized'
  fi
  chown -R mysql:mysql "${DATADIR}"
#
  message "Searching for custom MariaDB configs in ${INITDBDIR}..."
  CFGS=$(find "${INITDBDIR}" -name '*.cnf')
  if [[ -n "${CFGS}" ]]; then
    cp -vf "${CFGS}" /etc/my.cnf.d/
  fi
#
  message "Validating configuration..."
  validate_cfg "${@}"
  SOCKET="$(get_cfg_value 'socket' "$@")"
  gosu mysql "$@" --skip-networking --socket="${SOCKET}" &
  PID="${!}"
  mysql=( mysql --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" )

  for second in {30..0}; do
    [[ ${second} -eq 0 ]] && error 'MariaDB Enterprise server failed to start!' &&  exit 1
    if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
      break
    fi
    message 'Bringing up MariaDB Enterprise server...'
    sleep 1
  done
#
  if [[ -z "${MARIADB_INITDB_SKIP_TZINFO}" ]]; then
    # sed is for https://bugs.mysql.com/bug.php?id=20545
    message "Loading TZINFO"
    mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql
  fi
#
  if [[ -n "${MARIADB_RANDOM_ROOT_PASSWORD}" ]]; then
    MARIADB_ROOT_PASSWORD="'"
    while [[ "${MARIADB_ROOT_PASSWORD}" = *"'"* ]] || [[ "${MARIADB_ROOT_PASSWORD}" = *"\\"* ]]; do
      export MARIADB_ROOT_PASSWORD="$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64)"
    done
    message "=-> GENERATED ROOT PASSWORD: ${MARIADB_ROOT_PASSWORD}"
  fi
#
  if [[ -n "${MARIADB_DATABASE}" ]]; then
    message "Trying to create database with name ${MARIADB_DATABASE}"
    echo "CREATE DATABASE IF NOT EXISTS '${MARIADB_DATABASE}'" | "${mysql[@]}"
  fi
#
  if [[ -n "${MARIADB_USER}" ]] && [[ -n "${MARIADB_PASSWORD}" ]]; then
    message "Trying to create user ${MARIADB_USER} with password set"
    echo "CREATE USER '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';" | "${mysql[@]}"
    if [[ -n "${MARIADB_DATABASE}" ]]; then
      message "Trying to set all privileges on ${MARIADB_DATABASE} to ${MARIADB_USER}..."
      echo "GRANT ALL ON '${MARIADB_DATABASE}'.* TO '${MARIADB_USER}'@'%';" | "${mysql[@]}"
    fi
  else
    message "Skipping MariaDB user creation, both MARIADB_USER and MARIADB_PASSWORD must be set"
  fi
#
  for _file in "${INITDBDIR}"/*; do
    case "${_file}" in
      *.sh)
        message "Running shell script ${_file}"
        . "${_f}"
        ;;
      *.sql)
        message "Running SQL file ${_file}"
        "${mysql[@]}" < "${_file}"
        echo
        ;;
      *.sql.gz)
        message "Running compressed SQL file ${_file}"
        zcat "${_file}" | "${mysql[@]}"
        echo
        ;;
      *)
        message "Ignoring ${_file}"
        ;;
    esac
  done
#
# Reading password from docker filesystem (bind-mounted directory or file added during build)
  [[ -z "${MARIADB_ROOT_HOST}" ]] && MARIADB_ROOT_HOST='%'
  [[ -f "${MARIADB_ROOT_PASSWORD}" ]] && MARIADB_ROOT_PASSWORD=$(cat "${MARIADB_ROOT_PASSWORD}")
  if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
    message "ROOT password has been specified for image, trying to update account..."
    echo "CREATE USER IF NOT EXISTS 'root'@'${MARIADB_ROOT_HOST}' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';" | "${mysql[@]}"
    echo "GRANT ALL ON *.* TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION;" | "${mysql[@]}"
    echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" | "${mysql[@]}"
  fi
#
###
  if ! kill -s TERM "${PID}" || ! wait "${PID}"; then
    error "MariaDB Enterprise server init process failed!"
    exit 1
  fi
#
fi
#
# Finally
message "MariaDB Enterprise ${ES_VERSION} is ready for start!"
touch /es-init.completed
#
exec gosu mysql "$@" 2>&1 | tee -a /var/log/mariadb-error.log





