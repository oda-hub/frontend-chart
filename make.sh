
function create-secrets() {
    kubectl -n $ODA_NAMESPACE delete secret frontend-settings-php

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
         --set image.tag="$(cd frontend-container; bash make.sh compute-version)" 
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

function forward() {
    kubectl port-forward deployments/oda-frontend -n $ODA_NAMESPACE 8002:80
}

function drush-cc() {
    kubectl exec -it deployments/oda-frontend -n $ODA_NAMESPACE -- bash -c 'cd /var/www/astrooda; ~/.composer/vendor/bin/drush cc all'
}

function drush-extensions() {
    kubectl exec -it deployments/oda-frontend -n oda-staging -- bash -c '
        cd /var/www/astrooda; 
        ~/.composer/vendor/bin/drush dis astrooda_magic -y
        ~/.composer/vendor/bin/drush en astrooda_spi_acs -y
        '
}

$@
