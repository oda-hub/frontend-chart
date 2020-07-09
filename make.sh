
function create-secret() {
    echo
#    kubectl -n staging-1-3 delete secret dispatcher-conf
#    kubectl -n staging-1-3 create secret generic dispatcher-conf --from-file=conf_env.yml=dispatcher/conf/conf_env.yml
}

function install() {
    set -x
    helm -n ${NAMESPACE:?} install oda-frontend . --set image.tag="$(cd frontend-container; git describe --always)"
}

function upgrade() {
    set -x
    helm upgrade -n ${NAMESPACE:?} oda-frontend . --set image.tag="$(cd frontend-container; git describe --always)"
}

$@
