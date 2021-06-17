
function create-secrets() {
    kubectl -n ${ODA_NAMESPACE:?} delete secret frontend-settings-php

    (
        rm -fv private/drupal7_sites_default_settings.php
        umask 0066
        PASSWORD=$(cat private/astrooda-user) j2 config/drupal7_sites_default_settings.php.template -e PASSWORD > private/drupal7_sites_default_settings.php
    )
   

    kubectl -n $ODA_NAMESPACE create secret generic frontend-settings-php --from-file=drupal7_sites_default_settings.php=private/drupal7_sites_default_settings.php
}

function upgrade() {
    set -x
    helm upgrade -n ${ODA_NAMESPACE:?} --install oda-frontend . \
         -f $(bash <(curl https://raw.githubusercontent.com/oda-hub/dispatcher-chart/master/make.sh) site-values) \
         --set image.tag="$(cd frontend-container; bash make.sh compute-version)"  \
         --set postfix.image.tag="$(cd postfix-container; git describe --always --tags)" $@
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

    sleep 1

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

function db() {
    git clone git@github.com:oda-hub/frontend-drupal7-db-for-astrooda.git -b master drupal7-db-for-astrooda || (cd drupal7-db-for-astrooda; git checkout master; git pull)
    run-sql <(echo "USE astrooda;"; cat drupal7-db-for-astrooda/drupal7-db-for-astrooda.sql)
}

function dump-db() {
    # this all should be done in a k8s/job
    out_sql=${1:?}


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
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c 'cd /var/www/astrooda; ~/.composer/vendor/bin/drush '"${@}"
}

function drush-cc() {
    drush 'cc all'
}

function drush-reinstall() {
    instrument=${1:?}
    kubectl exec -it deployments/oda-frontend -n oda-staging -- bash -c '
        cd /var/www/astrooda; 
        ~/.composer/vendor/bin/drush dre astrooda_'${instrument}' -y
        '
}

function drush-extensions() {
    kubectl exec -it deployments/oda-frontend -n oda-staging -- bash -c '
        cd /var/www/astrooda; 
        ~/.composer/vendor/bin/drush dis astrooda_magic -y
        ~/.composer/vendor/bin/drush en astrooda_spi_acs -y
        '
}

function reset-drupal-admin() {
    (
        umask 0066
        rm -fv private/drupal-admin
        openssl rand -base64 32 > private/drupal-admin
    )
    kubectl exec -it deployments/oda-frontend -n oda-staging -- bash -c 'cd /var/www/astrooda; ~/.composer/vendor/bin/drush upwd --password="'$(cat private/drupal-admin)'" sitamin'
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
    run-sql <(echo "use astrooda; update variable set value='s:4:\"1440\";' where name='jwt_link_expiration';")

    drush-cc
}

function jwt_key_print() {
    run-sql <(echo "use astrooda; select * from variable where name='jwt_link_key';")
}

function jwt_key_update() {
    run-sql <(echo "use astrooda; update variable set value='s:"$(< private/jwt-key wc -c | awk '{print $1-1}')":\""$(cat private/jwt-key | xargs)"\";' where name='jwt_link_key';")
}

$@
