#!/bin/bash

# Set to 'true' to skip master nodes, 'false' to include them.
SKIP_MASTERS=true

# Get all node names
if [ "$SKIP_MASTERS" = true ]; then
  echo "Getting worker nodes..."
  NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o jsonpath='{.items[*].metadata.name}')
else
  echo "Getting all nodes..."
  NODES=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')
fi

if [ -z "$NODES" ]; then
  echo "No nodes found. Please check your 'oc' configuration and node labels."
  exit 1
fi

echo "The following nodes will be rebooted:"
for node in $NODES; do
  echo "- $node"
done

read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi


for node in $NODES; do
  echo "--------------------------------------------------"
  echo "Processing node: $node"
  echo "--------------------------------------------------"

  echo "Step 1: Draining node $node..."
  if ! oc adm drain "$node" --force --ignore-daemonsets --delete-emptydir-data; then
    echo "Failed to drain node $node. Skipping to next node."
    continue
  fi

  echo "Step 2: Rebooting node $node via oc debug..."
  # Use oc debug to reboot the node
  timeout 10s oc debug node/"$node" -- chroot /host systemctl reboot || true
  echo "Reboot command sent to node $node"

  echo "Step 3: Waiting for node $node to come back online..."
  # Wait for the node to become unavailable first
  timeout 60s bash -c "while oc get node \"$node\" > /dev/null 2>&1; do sleep 5; done"

  # Wait for the node to become ready
  echo "Node is offline. Waiting for it to become Ready..."
  if ! timeout 600s bash -c "until oc wait --for=condition=Ready node/\"$node\"; do sleep 5; done"; then
      echo "Node $node did not become Ready within 10 minutes. Please check it manually."
      continue
  fi


  echo "Step 4: Uncordoning node $node..."
  if ! oc adm uncordon "$node"; then
    echo "Failed to uncordon node $node. Please uncordon it manually."
  fi

  echo "Node $node has been successfully rebooted and uncordoned."
done

echo "--------------------------------------------------"
echo "All specified nodes have been processed."
echo "--------------------------------------------------"

echo "Performing cluster health check..."
oc get clusteroperators
oc get nodes
oc get pods --all-namespaces -o wide