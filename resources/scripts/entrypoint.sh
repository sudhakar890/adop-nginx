#!/bin/bash
set -e

if [ "$CUSTOM_CONF" == "false" ] || [ -z "$(ls -A "/etc/nginx")" ] ; then
  echo "reloading nginx configuration data from the container" ;
  cp -R /resources/configuration/* /etc/nginx/ ;
fi

if [ "$CUSTOM_HTML" == "false" ] || [ -z "$(ls -A "/usr/share/nginx/html")" ] ; then
  echo "reloading HTML landing page and release notes data from the container" ;
  cp -R /resources/release_note/* /usr/share/nginx/html/ ;
fi

# Auto populate the release note page with the blueprints
/resources/scripts/reload_release_notes.sh

# Copy and replace tokens
if [ "$CUSTOM_CONF" == "false" ] || [ -z "$(ls -A "/etc/nginx/nginx.conf")" ] ; then 
  perl -p -i -e 's/###([^#]+)###/defined $ENV{$1} ? $ENV{$1} : ""/eg' < "/templates/configuration/nginx.conf" 2> /dev/null 1> "/etc/nginx/nginx.conf"
fi
if [ "$CUSTOM_CONF" == "false" ] || [ -z "$(ls -A "/etc/nginx/sites-enabled")" ] ; then 
  perl -p -i -e 's/###([^#]+)###/defined $ENV{$1} ? $ENV{$1} : "$1 must be defined"/eg' < "/templates/configuration/sites-enabled/tools-context.conf" 2> /dev/null 1> "/etc/nginx/sites-enabled/tools-context.conf"
  perl -p -i -e 's/###([^#]+)###/defined $ENV{$1} ? $ENV{$1} : "$1 must be defined"/eg' < "/templates/configuration/sites-enabled/selenium.conf" 2> /dev/null 1> "/etc/nginx/sites-enabled/selenium.conf"
fi

# wait for all downstream services to be up and running
# This is a temporary solution that allows NGINX to wait for all dependencies and after start, this should be removed when 
# the depends_on see https://github.com/docker/compose/pull/686 and https://github.com/docker/compose/issues/2682 is introduced
# on docker compose
SLEEP_TIME=2
declare -a DEPENDENCIES=( "kibana:5601" "gerrit:8080/gerrit" "jenkins:8080" "sonar:9000" "sensu-uchiwa:3000" "nexus:8081" )
for d in ${DEPENDENCIES[@]}; do 
  echo "waiting for $d to be available";
  # use wget as already installed... 
  # We are checking for response codes that are not of class 5xx the most common are below, the list does not 
  # try to be exaustive, it only consider the response code that will guarantee NGINX to start when all dependencies are 
  # available.
  until wget -S -O - http://$d 2>&1 | grep "HTTP/" | awk '{print $2}' | grep "200\|404\|403\|401\|301\|302" &> /dev/null
  do
      echo "$d unavailable, sleeping for ${SLEEP_TIME}"
      sleep "${SLEEP_TIME}"
  done
done

/usr/sbin/nginx
