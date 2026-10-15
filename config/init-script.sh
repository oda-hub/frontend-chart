#!/bin/bash

# Fail fast: any failing command (also inside a pipe) stops the init container,
# instead of silently leaving a half-configured Drupal behind
set -eo pipefail
set -x

# Generate settings.php from template
cd /patched-files
cp /frontend-config/settings.php settings.php
sed -i "s/%%MYSQL_PASSWORD%%/${MYSQL_PASSWORD}/" settings.php

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

cd /var/www/mmoda
PATH=~/.composer/vendor/bin:$PATH

drush -y updb

# Enable the mmoda modules. Already enabled modules stay enabled.
# Do NOT disable/uninstall/reinstall:
# uninstalling mmoda deletes mmoda_settings and the help pages.
drush en -y mmoda
drush en -y $MMODA_MODULES_FORCE_ENABLE


chmod -R 777 /var/www/mmoda/sites/default/files

#reset drupal admin
drush user-create admin --password=$DRUPAL_PW || true
# user-create will fail with default dump as it already exists, that's ok
drush sql-query "UPDATE users SET mail='$SITE_EMAIL_FROM' WHERE name='admin';"
drush user-unblock admin # in case it was blocked in the dump
drush user-add-role "administrator" admin
drush upwd --password=$DRUPAL_PW admin

drush vset -y jwt_link_expiration $JWT_EXPIRATION
drush vset -y jwt_link_key $JWT_KEY
drush vset -y jwt_link_url $JWT_URL


drush vset -y site_mail $SITE_EMAIL_FROM
drush vset -y swiftmailer_sender_email $SITE_EMAIL_FROM

emails_to_arr=(${EMAILS_TO//,/ })
emails_to_json=$(printf ', "%s"' ${emails_to_arr[@]})
emails_to_json="[${emails_to_json:2}]"

# support_email: used in callback
export SUPPORT_EMAIL_TO="${emails_to_arr[0]}"
drush php-eval '$s = variable_get("mmoda_settings", array());
                $s["support_email"] = array(getenv("SITE_EMAIL_FROM"), getenv("SUPPORT_EMAIL_TO"));
                variable_set("mmoda_settings", $s);'

drush vset --format=json --exact --yes update_notify_emails $emails_to_json
drush vset --yes webform_default_from_address $SITE_EMAIL_FROM

for form_id in 383 392; do
    query="CREATE TEMPORARY TABLE webform_emails_tmp AS SELECT * FROM webform_emails WHERE nid=$form_id LIMIT 1;"
    query+="DELETE FROM webform_emails WHERE nid=$form_id;"
    for (( i=0; i<${#emails_to_arr[@]}; i++ )); do
        query+="UPDATE webform_emails_tmp SET eid=$((i+1)), email=\"${emails_to_arr[i]}\", from_address=\"$SITE_EMAIL_FROM\";"
        query+="INSERT INTO webform_emails SELECT * FROM webform_emails_tmp;"
    done

    drush sql-query "$query"
done

drush sql-query "DELETE FROM webform_emails WHERE nid=384 AND eid>1;"

drush vset --yes swiftmailer_smtp_host $swiftmailer_smtp_host
drush vset --yes swiftmailer_smtp_port $swiftmailer_smtp_port

# password/username/encryption are empty for SMTP without authentication:
# "drush vset" without a value fails, so only set them when they are not empty
[ -z "$swiftmailer_smtp_password" ] || drush vset --yes swiftmailer_smtp_password "$swiftmailer_smtp_password"
[ -z "$swiftmailer_smtp_username" ] || drush vset --yes swiftmailer_smtp_username "$swiftmailer_smtp_username"
[ -z "$swiftmailer_smtp_encryption" ] || drush vset --yes swiftmailer_smtp_encryption "$swiftmailer_smtp_encryption"

echo "{\"client_id\": \"$openid_client_id\", \"client_secret\": \"$openid_client_secret\", \"github_scopes\": \"user:email\"}" | 
    drush vset --yes --exact --format=json openid_connect_client_github -

if [ -f /backups/state-snapshot.sql ]; then
    echo run-sql /backups/state-snapshot.sql
else
    echo "No state-snapshot.sql found in /backups"
fi

drush cc -y all

# Sanity check: fail the init if mmoda_settings is incomplete
drush php-eval '$s = variable_get("mmoda_settings", array());
                if (empty($s["common"]) || empty($s["instruments"])) {
                    fwrite(STDERR, "FATAL: mmoda_settings is incomplete\n"); exit(1);
                }
                print "mmoda_settings OK: " . count($s["instruments"]) . " instruments\n";'
