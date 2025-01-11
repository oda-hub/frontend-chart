#!/bin/bash
set -x

# Install jq if not available
JQ_URL=https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
JQ_BIN=/usr/local/bin/jq
which jq 2>&1 > /dev/null || { curl -sfL $JQ_URL -o $JQ_BIN && chmod +x $JQ_BIN ; }

# Generate settings.php from template
cd /patched-files
curl https://raw.githubusercontent.com/oda-hub/frontend-chart/master/config/drupal7_sites_default_settings.php.template -o settings.php
sed -i "s@{{ mmoda_base_url }}@${MMODA_BASE_URL}@" settings.php
sed -i "s/{{env.PASSWORD}}/${MYSQL_PASSWORD}/" settings.php

# avoid db deadlocks, see https://groups.drupal.org/node/415883
cat <<- 'EOF' >> settings.php
$databases['default']['default']['init_commands'] = array(
    'isolation' => "SET SESSION transaction_isolation='READ-COMMITTED'"
);
EOF

echo '#####'
cat settings.php
echo '#####'

cp settings.php /var/www/mmoda/sites/default/settings.php
cp /var/www/mmoda/sites/all/modules/mmoda/mmoda.nameresolver.inc .
sed -i 's@$local_name_resolver_url = "https://resolver-prod.obsuks1.unige.ch/api/v1.1/byname/";@$local_name_resolver_url = "{{ .Values.resolver_endpoint }}";@'  mmoda.nameresolver.inc

cp -rfv /frontend-default-files/* /var/www/mmoda/sites/default/files

[ -d /instruments-dir ] && cp -rfv /var/www/mmoda/sites/all/modules/mmoda/instruments/* /instruments-dir
# other way around. If there were instruments initialised, they need to be in the fs 
[ -d /instruments-dir ] && cp -rfv /instruments-dir/* /var/www/mmoda/sites/all/modules/mmoda/instruments/

# wait db
function run-sql() {
    mysql -h mysql -u astrooda -p$MYSQL_PASSWORD astrooda < ${1:?}
}
while ! run-sql <(echo ";") ; do 
    sleep 10
done

function drush() {
    cd /var/www/mmoda
    ~/.composer/vendor/bin/drush "$@"
}

drush -y updb

# Drush reinstall all mmoda modules
ALL_MMODA_MODULES=`drush pm-list --type=module --format=json | jq -r '[ keys[] | select(startswith("mmoda_")) ] | join(",")'`
ENABLED_MMODA_MODULES=`drush pm-list --type=module --status=enabled --format=json | jq -r '[ keys[] | select(startswith("mmoda_")) ] | join(",")'`
drush dis -y mmoda 
drush pm-uninstall -y $ALL_MMODA_MODULES
drush pm-uninstall -y mmoda
drush en -y mmoda 
drush en -y $ENABLED_MMODA_MODULES


chmod -R 777 /var/www/mmoda/sites/default/files

#reset drupal admin
drush user-create admin --password=$DRUPAL_PW
drush user-add-role "administrator" admin
drush upwd --password=$DRUPAL_PW admin
# what about admin email?

drush vset -y jwt_link_expiration $JWT_EXPIRATION
drush vset -y jwt_link_key $JWT_KEY
drush vset -y jwt_link_url $JWT_URL

# drush vset -y site_mail $SITE_MAIL
# drush vset -y swiftmailer_sender_email $SWIFTMAIL_SENDER_EMAIL



#Example set variable in array
drush vget --format=json mmoda_settings | 
   jq '.mmoda_settings.support_email = ["no-reply@odahub.fr", "savchenko@apc.in2p3.fr"] | 
   .mmoda_settings' | 
   drush vset --format=json --exact --yes mmoda_settings - 2>/dev/null # because we don't want to see all array in log



drush cc -y all 