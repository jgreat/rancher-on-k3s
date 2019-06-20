#!/bin/bash


function restore {
    local file=${1}
    sleep 0.1
    local out=$(kubectl create -f ${file} 2>&1)
    if [[ "${out}" =~ "Error" ]]; then
        sleep 0.1
        out=$(kubectl apply -f $file 2>&1)
# Would like to edit/ignore Warning: kubectl apply should be used on resource created by either kubectl create --save-config or kubectl apply 
        if [[ "${out}" =~ "Error" ]]; then
            echo ${out}
            exit 1
        fi
    fi
    echo ${out}
}

backup_path=${1}
if [[ -z $backup_path ]]; then
    echo "$0 <backup dir>"
    echo "backup dir required"
    exit 1
fi

cp -R ${backup_path} /tmp/${backup_path}
user_files=( $(find /tmp/${backup_path}/global/users.management.cattle.io -type f -print ) )

for f in ${user_files[@]}; do
    name=$(cat ${f} | jq -r ". | select(.username == \"admin\") | .metadata.name")
    if [[ ${name} ]]; then
        backup_admin=${name}
        rm -f ${f}
        break
    fi
done

if [[ -z ${backup_admin} ]]; then
    echo "Error: No admin user found in backups"
    exit 1
fi

target_admin=$(kubectl get users.management.cattle.io -o json | jq -r '.items[] | select(.username == "admin") | .metadata.name')
if [[ $? > 0 ]]; then
    echo "ERROR: not able to get target cluster admin user."
    echo "  Can kubectl connect to target cluster?"
    echo "  Is Rancher installed and bootstraped?"
    exit 1
fi

echo "Backup cluster admin user: ${backup_admin}"
echo "Target cluster admin user: ${target_admin}"

if [[ "${target_admin}" == "${backup_admin}" ]]; then
    echo "ERROR: User from backup is same as user from target. Make sure your kubeconfig is pointing to the new cluster."
    exit 1
fi

echo "Stopping Rancher Deployment (scale --replicas=0)"
kubectl -n cattle-system scale --replicas=0 deployment rancher --timeout=60s

echo "Replace instances of admin user"
grep -rl "${backup_admin}" /tmp/${backup_path} | xargs sed -i "s/${backup_admin}/${target_admin}/g"

echo "Get namespace manifests"
n_manifests=( $(find /tmp/${backup_path}/namespaces -type f -print | sort) )
echo "Get global manifests"
g_manifests=( $(find /tmp/${backup_path}/global -type f -print | sort ) )

for g in ${g_manifests[@]}; do
    restore ${g}
done

for n in ${n_manifests[@]}; do
    restore ${n}
done

echo "Starting Rancher Deployment"
kubectl -n cattle-system scale --replicas=3 deployment rancher --timeout=60s

rm -rf /tmp/${backup_path}
