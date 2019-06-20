#!/bin/bash

# Backup Rancher resources.

# echo to stderr
echoerr() { echo "$@" 1>&2; }

# Rancher namespaces
get_namespaces() {
    echoerr "--- Gathering Rancher namespaces"
    local namespaces=$(kubectl get ns -o json)
    local ns=($(echo ${namespaces} | jq -r '.items[] | select(.metadata.name | test("^c-")) | .metadata.name'))
    ns+=($(echo ${namespaces} | jq -r '.items[] | select(.metadata.name | test("^p-"))| .metadata.name'))
    ns+=($(echo ${namespaces} | jq -r '.items[] | select(.metadata.name | test("^user-"))| .metadata.name'))
    ns+=($(echo ${namespaces} | jq -r '.items[] | select(.metadata.name | test("^u-"))| .metadata.name'))
    ns+=("cattle-global-data" "cattle-system" )

    # Filter out the projects in the "local" cluster.
    for del in ${local_projects[@]}; do
        ns=("${ns[@]/$del}")
    done

    # # Filter out "admin" user
    # ns=("${ns[@]/$admin_user}")

    echo ${ns[@]}
}

get_namespaced_res_types() {
    echoerr "--- Gathering Rancher namespaced resources types"

    local namespaced_resources=($(kubectl api-resources --no-headers --namespaced=true -o name | grep cattle.io))
    namespaced_resources+=("secrets" "configmaps" "roles" "rolebindings" "serviceaccounts")

    # Filter out resources
    local ignored_resources_types=("catalogtemplates.management.cattle.io" "catalogtemplateversions.management.cattle.io")
    for del in ${ignored_resources_types[@]}; do
        namespaced_resources=("${namespaced_resources[@]/$del}")
    done

    echo ${namespaced_resources[@]}
}

get_global_res_types() {
    echoerr "--- Gathering Rancher global resources types"

    local global_resources=($(kubectl api-resources --no-headers --namespaced=false -o name | grep cattle.io))
    global_resources+=("clusterrolebindings" "clusterroles")

    echo ${global_resources[@]}
}

function scrape_namespace {
    local namespace=${1}
    local resource_types=($(get_namespaced_res_types))
    echoerr "--- Backing up namespace ${namespace}"
    local ns_dir="backups-${date}/namespaces/${namespace}"
    mkdir -p ${ns_dir}
    for resource in ${resource_types[@]}; do
        local dir="${ns_dir}/${resource}"
        mkdir -p ${dir}
        local objects=$(kubectl -n ${namespace} get ${resource} -o json | jq -r '.items[]')
        if [[ ! -z $objects ]]; then
            local names=($(echo ${objects} | jq -r '.metadata.name' ))
            for name in ${names[@]}; do
                # Filter out common resources
                for filter in ${namespaced_filters[@]}; do
                    if [[ "${resource}/${name}" =~ ^${filter} ]]; then
                        continue 2
                    fi
                done
                echoerr "[${namespace}] Exporting resource: ${resource}/${name}"
                echo ${objects} | jq -r ". | select(.metadata.name == \"${name}\") | ${manifest_keys_del}" > ${dir}/${name}.json
            done;
        fi
    done
    kubectl get ns ${namespace} -o json | jq -r ". | ${manifest_keys_del}" > ${ns_dir}/00-${namespace}.json
}

function remove_user {
    local id=${1}
    local files=$(find ./backups-${date}/global/users.management.cattle.io -type f -print | sort )
    for f in ${files[@]}; do
        cat ${f} | jq -e ".principalIds[] | select(. == \"system://${id}\")" 2>&1 >/dev/null
        if [[ $? == 0 ]]; then
            local name=$(cat ${f} | jq ".metadata.name")
            echo "removing ${f} for User $id"
            rm -f ${f}
            # remove_clusterrolebinding ${name}
            # remove_role ${name}
            # remove_token ${name}
            # remove_globalrolebinding ${name}
        fi
    done
}

# # Clean after collection.
# admin_user=$(kubectl get users.management.cattle.io -o json | jq -r '.items[] | select(.username == "admin")')

# might need to get more specific with .status on resources (I don't want cluster to recreate.)
# Apply order might matter

date=$(date +%Y%m%d-%H:%M:%S)
#    .metadata.ownerReferences,
#    .status
manifest_keys_del=$(cat <<EOF
del(
    .metadata.creationTimestamp,
    .metadata.generation,
    .metadata.resourceVersion,
    .metadata.selfLink,
    .metadata.uid
)
EOF
)
namespaced_filters=(
    "secrets/default-token"
    "serviceaccounts/default"
)
global_filters=(
    "catalogs.management.cattle.io/library"
    "catalogs.management.cattle.io/system-library"
    "clusters.management.cattle.io/local"
)


rancher_namespace="cattle-system"

echo "Stopping rancher deployment (scale --replicas=0)"
kubectl -n ${rancher_namespace} scale --replicas=0 deployment rancher --timeout=60s

admin_user=$(kubectl get users.management.cattle.io -o json | jq -r '.items[] | select(.username == "admin") | .metadata.name')
local_projects=( $(kubectl -n 'local' get projects.management.cattle.io --no-headers | awk '{print $1}') )
local_projects+=( "local" )
ns=( $(get_namespaces) )
# ns_res_types=( $(get_namespaced_res_types) )
global_res_types=( $(get_global_res_types) )

echoerr "Found namespaces:"
for n in ${ns[@]}; do
    echoerr "  ${n}"
done
echoerr "  Found Rancher namespaced resource types:"
for r in ${ns_res_types[@]}; do
    echoerr "    ${r}"
done
echoerr "  Found Rancher global resource types:"
for r in ${global_res_types[@]}; do
    echoerr "    ${r}"
done

for namespace in ${ns[@]}; do
    scrape_namespace ${namespace}
done

echoerr "--- Backing up global resources"
for resource in ${global_res_types[@]}; do
    dir="backups-${date}/global/${resource}"
    mkdir -p ${dir}
    objects=$(kubectl get ${resource} -o json | jq -r '.items[]')
    if [[ ! -z $objects ]]; then
        names=($(echo ${objects} | jq -r '.metadata.name'))
        for name in ${names[@]}; do
            for filter in ${global_filters[@]}; do
                if [[ "${resource}/${name}" =~ ^${filter} ]]; then
                    continue 2
                fi
            done
            echoerr "[global] Exporting resource: ${resource}/${name}"
            echo ${objects} | jq -r ". | select(.metadata.name == \"${name}\") | ${manifest_keys_del}" > ${dir}/${name}.json
        done;
    fi
done


# Clean up admin user resources
echo "Admin User: ${admin_user}"
# Clean up local cluster resources
echo "Local Cluster Projects: ${local_projects[@]}"

for p in ${local_projects[@]}; do
    remove_user ${p}
done

# Remove namespace manifest for global-cattle-data and cattle-system and don't recreate admin namespace.
rm -f backups-${date}/namespaces/cattle-global-data/00-cattle-global-data.json 2>&1 >/dev/null
rm -f backups-${date}/namespaces/cattle-system/00-cattle-system.json 2>&1 >/dev/null
rm -f backups-${date}/namespaces/${admin_user}/00-${admin_user}.json 2>&1 >/dev/null
