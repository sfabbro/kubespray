#!/bin/bash

[ $# -lt 2 ] && \
    echo "usage: $(basename $0) <cluster_name> <master_ip_to_ssh>" && \
    exit

install_kubectl() {
    sudo apt-get update && sudo apt-get install -y apt-transport-https
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    sudo touch /etc/apt/sources.list.d/kubernetes.list 
    echo "deb http://apt.kubernetes.io/ kubernetes-bionic main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
}

ssh_user=core
cluster_name=$1
master_ip=$2

type -P kubectl || install_kubectl

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
	--server=https://${master_ip}:6443 \
	--certificate-authority=inventory/${cluster_name}/ca.pem

kubectl config set-credentials default-admin \
	--certificate-authority=inventory/${cluster_name}/ca.pem \
	--client-key=inventory/${cluster_name}/admin-key.pem \
	--client-certificate=inventory/${cluster_name}/admin.pem

kubectl config set-context default-system --cluster=default-cluster --user=default-admin
kubectl config use-context default-system
