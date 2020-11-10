export ENVIRONMENT=staging-1-3

function create-secret() {
    kubectl -n staging-1-3 delete secret frontend-settings-php

    (
        rm -fv private/drupal7_sites_default_settings.php
        umask 0066
        PASSWORD=$(cat private/astrooda-user) j2 config/drupal7_sites_default_settings.php.template -e PASSWORD > private/drupal7_sites_default_settings.php
    )
   

    kubectl -n staging-1-3 create secret generic frontend-settings-php --from-file=drupal7_sites_default_settings.php=private/drupal7_sites_default_settings.php
#    kubectl -n staging-1-3 delete secret dispatcher-conf
#    kubectl -n staging-1-3 create secret generic dispatcher-conf --from-file=conf_env.yml=dispatcher/conf/conf_env.yml
}

function upgrade() {
    set -x
    helm upgrade -n ${NAMESPACE:?} --install oda-frontend . --set image.tag="$(cd frontend-container; git describe --always)" --wait
}

function user() {
    (
      umask 0066
      openssl rand -base64  16 >  private/astrooda-user
    )
}


function run-sql() {
    sql=${1:?}


    kubectl port-forward svc/mysql 3307:3306 -n staging-1-3 &
    proxy=$!

    sleep 1

    MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace $ENVIRONMENT mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)

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
    git clone git@gitlab.astro.unige.ch:cdci/frontend/drupal7-db-for-astrooda.git -b staging-1.3 || (cd drupal7-db-for-astrooda; git checkout staging-1.3; git pull)
    run-sql <(echo "USE astrooda;"; cat drupal7-db-for-astrooda/drupal7-db-for-astrooda.sql)
}

function forward() {
    kubectl port-forward oda-frontend-dcd58c84c-mhzj9 -n staging-1-3 8000:80
}

$@
