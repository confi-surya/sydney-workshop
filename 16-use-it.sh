#!/bin/bash
set -x
export OS_CLOUD=openstack_helm

export OSH_EXT_NET_NAME="public"
export OSH_EXT_SUBNET_NAME="public-subnet"
export OSH_EXT_SUBNET="172.24.4.0/24"
export OSH_BR_EX_ADDR="172.24.4.1/24"
openstack stack create --wait \
  --parameter network_name=${OSH_EXT_NET_NAME} \
  --parameter physical_network_name=public \
  --parameter subnet_name=${OSH_EXT_SUBNET_NAME} \
  --parameter subnet_cidr=${OSH_EXT_SUBNET} \
  --parameter subnet_gateway=${OSH_BR_EX_ADDR%/*} \
  -t /opt/openstack-helm/tools/gate/files/heat-public-net-deployment.yaml \
  heat-public-net-deployment

export OSH_PRIVATE_SUBNET_POOL="10.0.0.0/8"
export OSH_PRIVATE_SUBNET_POOL_NAME="shared-default-subnetpool"
export OSH_PRIVATE_SUBNET_POOL_DEF_PREFIX="24"
openstack stack create --wait \
  --parameter subnet_pool_name=${OSH_PRIVATE_SUBNET_POOL_NAME} \
  --parameter subnet_pool_prefixes=${OSH_PRIVATE_SUBNET_POOL} \
  --parameter subnet_pool_default_prefix_length=${OSH_PRIVATE_SUBNET_POOL_DEF_PREFIX} \
  -t /opt/openstack-helm/tools/gate/files/heat-subnet-pool-deployment.yaml \
  heat-subnet-pool-deployment


export OSH_EXT_NET_NAME="public"
export OSH_VM_FLAVOR="m1.tiny"
export OSH_VM_KEY_STACK="heat-vm-key"
export OSH_PRIVATE_SUBNET="10.0.0.0/24"

# NOTE(portdirect): We do this fancy, and seemingly pointless, footwork to get
# the full image name for the cirros Image without having to be explicit.
export IMAGE_NAME=$(openstack image show -f value -c name \
  $(openstack image list -f csv | awk -F ',' '{ print $2 "," $1 }' | \
    grep "^\"Cirros" | head -1 | awk -F ',' '{ print $2 }' | tr -d '"'))

# Setup SSH Keypair in Nova
mkdir -p ${HOME}/.ssh
openstack keypair create ${OSH_VM_KEY_STACK} > ${HOME}/.ssh/id_rsa
chmod 600 ${HOME}/.ssh/id_rsa

openstack stack create --wait \
    --parameter public_net=${OSH_EXT_NET_NAME} \
    --parameter image="${IMAGE_NAME}" \
    --parameter flavor=${OSH_VM_FLAVOR} \
    --parameter ssh_key=${OSH_VM_KEY_STACK} \
    --parameter cidr=${OSH_PRIVATE_SUBNET} \
    -t /opt/openstack-helm/tools/gate/files/heat-basic-vm-deployment.yaml \
    heat-basic-vm-deployment

FLOATING_IP=$(openstack floating ip show \
  $(openstack stack resource show \
      heat-basic-vm-deployment \
      server_floating_ip \
      -f value -c physical_resource_id) \
      -f value -c floating_ip_address)

# SSH into the VM and check it can reach the outside world
ssh-keyscan "$FLOATING_IP" >> ~/.ssh/known_hosts
ssh -i ${HOME}/.ssh/id_rsa cirros@${FLOATING_IP} ping -q -c 1 -W 2 ${OSH_BR_EX_ADDR%/*}
