#!/bin/bash

# deployment script assumes:
# - you have a git clone of kubespray: https://github.com/kubernetes-incubator/kubespray.git
# - you have installed ansible, terraform and python-openstackclient
# - you have downloaded and sourced the openstack rc file for your tenant
# - you have generated an ssh key in ~/.ssh/id_rsa
# - you are running commands from the kubespray clone directory
# - you have run terraform init contrib/terraform/openstack

[ $# -lt 2 ] && \
    echo "usage: $(basename $0) <cluster_name> <openstack_rc_file>" && \
    exit

cluster_name=$1
openstack_rc=$2
ssh_private_key=~/.ssh/id_rsa

source ${openstack_rc}

# prepare cluster inventory
cp -LRp contrib/terraform/openstack/sample-inventory inventory/${cluster_name}
ln -s ../../contrib/terraform/openstack/hosts inventory/${cluster_name}
cp ${openstack_rc} inventory/${cluster_name}/

# prepare cluster for terraform
# some values still hardcoded to be worked out
cat <<EOF > inventory/${cluster_name}/cluster.tf
cluster_name = "${cluster_name}"
public_key_path = "${ssh_private_key}.pub"
image = "Container-Linux"
ssh_user = "core"

number_of_bastions = 0
number_of_etcd = 0

number_of_k8s_masters = 0
number_of_k8s_masters_no_etcd = 0
number_of_k8s_masters_no_floating_ip = 1
number_of_k8s_masters_no_floating_ip_no_etcd = 0
flavor_k8s_master = "$(openstack flavor show -c id -f value c2-7.5gb-31 2>/dev/null)"

number_of_k8s_nodes = 0
number_of_k8s_nodes_no_floating_ip = ${cluster_number_nodes}
flavor_k8s_node = "$(openstack flavor show -c id -f value c2-15gb-80 2>/dev/null)"

network_name = "${cluster_name}-network"
floatingip_pool = "$(openstack network list -c ID -f value --external)"
external_net = "$(openstack network list -c ID -f value --external)"
EOF

terraform init
terraform apply \
	  -state=inventory/${cluster_name}/terraform.tfstate \
	  -var-file=inventory/${cluster_name}/cluster.tf \
	  contrib/terraform/openstack 

# prepare ansible stuff
# changes from default to use coreos
sed -e 's|\(bootstrap_os:\).*|\1 coreos|' \
    -e 's|\(bin_dir:\).*|\1 /opt/bin|' \
    -e 's|\(cloud_provider:\).*|\1 openstack|' \
    -i inventory/${cluster_name}/group_vars/all.yml
sed -e -e 's|\(kube_network_plugin:\).*|\1 flannel|' \
sed -e -e 's|\(resolvconf_mode:\).*|\1 host_resolvconf|' \
    -i inventory/${cluster_name}/group_vars/k8s-cluster.yml

eval $(ssh-agent -s)
ssh-add ${ssh_private_key}

ansible-playbook --become -i inventory/${cluster_name}/hosts cluster.yml

# prepare kubectl
ssh ${ssh_user}@${master_ip} \
    sudo cat /etc/kubernetes/ssl/admin-${cluster_name}-k8s-master-1-key.pem \
    > inventory/${cluster_name}/admin-key.pem
ssh ${ssh_user}@${master_ip} \
    sudo cat /etc/kubernetes/ssl/admin-${cluster_name}-k8s-master-1.pem \
    > inventory/${cluster_name}/admin.pem
ssh ${ssh_user}@${master_ip} \
    sudo cat /etc/kubernetes/ssl/ca.pem \
    > inventory/${cluster_name}/ca.pem

kubectl config set-cluster default-cluster \
	--server=https://${master_internal_ip}:6443 \
	--certificate-authority=inventory/${cluster_name}/ca.pem

kubectl config set-credentials default-admin \
	--certificate-authority=inventory/${cluster_name}/ca.pem \
	--client-key=inventory/${cluster_name}/admin-key.pem \
	--client-certificate=inventory/${cluster_name}/admin.pem

kubectl config set-context default-system --cluster=default-cluster --user=default-admin
kubectl config use-context default-system
