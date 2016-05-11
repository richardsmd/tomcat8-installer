#!/bin/bash
#
# Setup Tomcat
#
# Author Mike Richards <richardsmd@pbworld.com>
#
# NOTE: script is *basically* idempotent. In other words, you can run it repeatedly without breaking things
# subsequent runs will litter /opt with tomcat-YYYYMMDD_HHMMSS directories containing old data

# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -u  # Referencing undefiend variables e.g., $FLOO will lead to an error
set -o pipefail  # Prevent pipeline errors from being masked
IFS=$'\n\t'

TOMCAT_ARCHIVE='apache-tomcat-8.0.33.tar.gz'
PSQL_DRIVER='postgresql-9.4.1208.jre7.jar'

TC_HOME='/opt/tomcat'
TC_CONF="${TC_HOME}/conf"
TC_LIB="${TC_HOME}/lib"

main() {
    verify_root
    configure_firewall
    create_tomcat_user
    create_tomcat_dest
    extract_tomcat
    extract_postgresql_driver
    set_ownership_and_permissions
    create_upstart_script
}

verify_root() {
    if [ `id -u` -ne 0 ]; then
        echo "You need root privileges to run this script"
        exit 1
    fi
}

configure_firewall() {
    grep -q -E '8080/tcp.+ALLOW.+10.1.118.0/24' <(ufw status) && echo "8080 allowed" || (\
        ufw allow from 10.1.118.0/24 to any port 8080 proto tcp && echo "8080 set to allowed from 10.1.118.0/24"
    )
}

create_tomcat_user() {
    grep -q '^tomcat:' /etc/passwd && echo 'Tomcat user exists' || (\
        adduser --system --uid 151 --ingroup www-data --home $TC_HOME tomcat && \
        echo 'Tomcat user created'
    )
}

create_tomcat_dest() {
    if [ -d "$TC_HOME" ]; then
        OLD="${TC_HOME}-$(date +%Y%m%d_%H%M%S)"
        mv "$TC_HOME" "$OLD"
        echo "Moved existing install to $OLD"
    fi
    mkdir -p "$TC_HOME"
}

extract_tomcat() {
    # extracts archive to specified directory, removing top-level dir included in archive
    tar -xf "$TOMCAT_ARCHIVE" -C "$TC_HOME" --strip-components=1
}

extract_postgresql_driver() {
  if [ ! -d "$TC_LIB" ]; then
    mkdir -p "$TC_LIB"
  fi
  cp "$PSQL_DRIVER" "$TC_LIB/$PSQL_DRIVER"
}

set_ownership_and_permissions() {
    chown -R tomcat:www-data "$TC_HOME"
}

create_upstart_script() {
    cat <<'EOF' > '/etc/init/tomcat.conf'
# tomcat service job file
# patterned from https://gist.github.com/alanfranz/6902429
description "Tomcat Service"
author "Ryan Avery <avery@pbworld.com>"

# when to start and stop the service (runlevel vs network-services)
start on runlevel [2345]
stop on runlevel [016]

# automatically restart process if crashed, but not more than 3 times in 10 seconds
respawn
respawn limit 3 10

# run as unprivileged user
setuid tomcat
setgid www-data

# stop upstart from handling stdout/stderr since we redirect it
console none

# custom environment variables
#env JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
env CATALINA_HOME=/opt/tomcat
env CATALINA_OPTS="-Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -server -Xms512m -Xmx1024m -XX:MaxPermSize=512m -XX:+UseParNewGC -XX:ParallelGCThreads=2"

# alternative method to manage tomcat using startup/shutdown scripts
# should not start and stop tasks in pre tasks, but it works
# see: http://askubuntu.com/questions/23113/
#pre-start exec ${CATALINA_HOME}/bin/startup.sh
#pre-stop exec ${CATALINA_HOME}/bin/shutdown.sh

# use catalina run instead of start so it will not fork and upstart can manage it
# start action - redirect output to catalina.out instead of /var/log/upstart/liferay
exec ${CATALINA_HOME}/bin/catalina.sh run >> ${CATALINA_HOME}/logs/catalina.out 2>&1

# cleanup temp directory after stop (example of script vs exec one-liner)
post-stop script
  echo "cleaning temp dir"
  rm -rf ${CATALINA_HOME}/temp/*
end script

EOF

    echo "Startup script created. Run 'service tomcat start' to turn it on. GOTO port 8080"
}

main
