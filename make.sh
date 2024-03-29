set -ex

ODA_NAMESPACE=${ODA_NAMESPACE:-$ODA_NAMESPACE}

SITE_VALUES=$(bash <(curl https://raw.githubusercontent.com/oda-hub/dispatcher-chart/master/make.sh) site-values)

export MODULE_LIST="$(< values-unige-dstic-staging.yaml awk -F: '/module_list/ {print $2}')"

function mattermost() {
    channel=${1:?}
    message=${2:-stdin}

    if [ $message == "stdin" ]; then
        message=$(cat)
    fi

    curl -i -X POST -H 'Content-Type: application/json' \
        -d '{"channel": "'"$channel"'", "text": "'"${message:?}"'"}' \
        ${MATTERMOST_HOOK:?}        
}


function create-secrets() {
    kubectl -n ${ODA_NAMESPACE:?} delete secret frontend-settings-php || true

    (
        # yet another templating level, not ideal
        rm -fv private/drupal7_sites_default_settings.php
        umask 0066
        PASSWORD=$(cat private/astrooda-user) j2 -f yaml config/drupal7_sites_default_settings.php.template $SITE_VALUES -e env > private/drupal7_sites_default_settings.php
    )
   

    kubectl -n $ODA_NAMESPACE create secret generic frontend-settings-php --from-file=drupal7_sites_default_settings.php=private/drupal7_sites_default_settings.php
}

function upgrade() {
    (cd frontend-container; bash make.sh compute-version > version-short.txt && cp -fv version.yaml version-short.txt ../) || \
        (echo "can not compute version, probably ok, will use:"; ls -l version.yaml)


    helm upgrade -n ${ODA_NAMESPACE:?} --install oda-frontend . \
         -f $SITE_VALUES \
         --wait \
         --set image.tag=a6e7cbd6  \
         --set postfix.image.tag="$(cd postfix-container; git describe --always --tags)" $@

    bash make.sh patch-resolver
    bash make.sh frontend-files-permissions
    bash make.sh drush-reinstall-all
    bash make.sh drush-cc
    
    python3 template.py | bash make.sh mattermost deployment-$ODA_NAMESPACE

}

function user() {
    (
      mkdir -p private
      umask 0066
      openssl rand -base64  16 >  private/astrooda-user
    )
}


function run-sql() {
    # this all should be done in a k8s/job
    sql=${1:?}


    kubectl port-forward svc/mysql 3307:3306 -n $ODA_NAMESPACE &
    proxy=$!

    sleep 3

    MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace $ODA_NAMESPACE mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)

    mysql --protocol=tcp -h 127.0.0.1 -P3307 -u root -p${MYSQL_ROOT_PASSWORD} < $sql

    kill -9 $proxy
}


function db-user() {
    (
        umask 0066
        rm -fv private/astrooda-user.sql
        PASSWORD=$(cat private/astrooda-user) j2 config/astrooda-user.sql.template -e PASSWORD  > private/astrooda-user.sql
        run-sql private/astrooda-user.sql
    )
}


#TODO: also store news, webform results
function db-users() {
    (
        run-sql ${1:?}
    )
}

function db() {
    git clone git@github.com:oda-hub/frontend-drupal7-db-for-astrooda.git -b master drupal7-db-for-astrooda || (cd drupal7-db-for-astrooda; git checkout master; git pull)
    run-sql <(echo "DROP DATABASE astrooda; CREATE DATABASE astrooda; USE astrooda;"; cat drupal7-db-for-astrooda/mmoda.sql)
    #run-sql <(echo "USE astrooda;"; cat drupal7-db-for-astrooda/drupal7-db-for-astrooda.sql)
}

function dump-db() {
    # this all should be done in a k8s/job
    out_sql=${1:-$ODA_NAMESPACE-$(date +%y%m%d_%H%M).sql}


    kubectl port-forward svc/mysql 3307:3306 -n $ODA_NAMESPACE &
    proxy=$!

    sleep 1

    MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace $ODA_NAMESPACE mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)

    mysqldump --protocol=tcp -h 127.0.0.1 -P3307 -u root -p${MYSQL_ROOT_PASSWORD} astrooda > $out_sql

    kill -9 $proxy
}

function forward() {
    kubectl port-forward deployments/oda-frontend -n $ODA_NAMESPACE 8002:80
}

function drush() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c 'cd /var/www/mmoda; ~/.composer/vendor/bin/drush '"${@}"
}
 
function frontend-default-files() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c 'cp -rfv /frontend-default-files/* /var/www/mmoda/sites/default/files/'
}

function frontend-files-permissions() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE   -- chmod -R 777 /var/www/mmoda/sites/default/files
}

function drush-cc() {
    drush 'cc all'
}


function drush-remove-all() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c '
        cd /var/www/mmoda; 
        ~/.composer/vendor/bin/drush dis -y mmoda;
        ~/.composer/vendor/bin/drush pm-uninstall -y '"$MODULE_LIST"'
        ~/.composer/vendor/bin/drush pm-uninstall -y mmoda;
        '
}



function drush-install-all() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c '
        cd /var/www/mmoda; 
        ~/.composer/vendor/bin/drush en -y mmoda;
        ~/.composer/vendor/bin/drush en -y '"$MODULE_LIST"';
        '
}

function drush-reinstall-all() {
    drush-remove-all
    drush-install-all

    frontend-files-permissions
    patch-resolver
}

function drush-extensions() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c '
        cd /var/www/mmoda; 
        ~/.composer/vendor/bin/drush pm-disable mmoda_magic -y
        ~/.composer/vendor/bin/drush pm-uninstall mmoda_magic -y
        ~/.composer/vendor/bin/drush dis mmoda_magic -y
        ~/.composer/vendor/bin/drush en mmoda_spi_acs -y
        '
}

function reset-drupal-admin() {
    (
        umask 0066
        rm -fv private/drupal-admin
        openssl rand -base64 32 > private/drupal-admin
    )
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c 'cd /var/www/mmoda; ~/.composer/vendor/bin/drush upwd --password="'$(cat private/drupal-admin)'" sitamin'
}

function update_news() {
    date=$(date) live=$(oda-node info 2>&1 | awk '/facts/ {gsub(" facts", "")} /live/' | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g") j2 -e date news.sql.template  > news.sql

    run-sql news.sql
}

function jwt_key_generate() {
    (
        umask 0066
        rm -fv private/jwt-key
        openssl rand -base64 32 > private/jwt-key
    )
}

function jwt_link_expiration() {
    # this should be really in a Job and value derived from chart values

    echo -e "\033[32m was: \033[0m"
    run-sql <(echo "use astrooda; select * from variable where name='jwt_link_expiration';")
    run-sql <(echo "use astrooda; update variable set value='s:5:\"20160\";' where name='jwt_link_expiration';")

    drush-cc
}

function jwt_key_print() {
    run-sql <(echo "use astrooda; select * from variable where name='jwt_link_key';")
}

function swiftmailer_path_print() {
    run-sql <(echo "use astrooda; select * from variable where name='swiftmailer_path';")
}

function ckeditor_path_print() {
    run-sql <(echo "use astrooda; select * from ckeditor_settings;")
}

function jwt_key_update() {
    run-sql <(echo "use astrooda; update variable set value='s:"$(< private/jwt-key wc -c | awk '{print $1-1}')":\""$(cat private/jwt-key | xargs)"\";' where name='jwt_link_key';")
}

function jwt_configure() {
    jwt_link_expiration
    jwt_key_update
}

function swiftmailer_path_print() {
    run-sql <(echo "use astrooda; select * from variable where name='swiftmailer_path';")
}

function swiftmailer_path_update() {
    run-sql <(echo "use astrooda; update variable set value='s:30:"vendor/swiftmailer/swiftmailer";' where name='swiftmailer_path';")
}

function clone_container() {
    frontend_container_revision=$(cat frontend_container_revision.txt)
    git clone https://github.com/oda-hub/frontend-container frontend-container || echo "can not clone, exists?"
    (cd frontend-container; git reset --hard ) | awk '{print "\033[32m"$0"\033[0m"}'

    git clone https://github.com/oda-hub/postfix-container postfix-container
}

function patch-resolver() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- sed -i 's@$local_name_resolver_url = "http://cdcihn/tnr-1.2/api/v1.1/byname/";@$local_name_resolver_url = "https://resolver-prod.obsuks1.unige.ch/api/v1.1/byname/";@'  /var/www/mmoda/sites/all/modules/mmoda/mmoda.nameresolver.inc
}

#modules/astrooda/instruments/astrooda_jemx/astrooda_jemx.inc:      'OSA11.2-beta' => 'OSA11.2-beta'

function patch-osa112() {
    for ins in jemx isgri; do
        kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- sed -i "s@'OSA11.1' => 'OSA11.1',@@; s@OSA11.2-beta@OSA11.2@g"  \
                /var/www/astrooda/sites/all/modules/astrooda/instruments/astrooda_${ins}/astrooda_${ins}.inc
    done
}

$@
