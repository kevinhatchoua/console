#!/usr/bin/env bash
#
# Seed NADs and VirtualMachines for local KubeVirt / networking console demos.
# Idempotent: skips resources that already exist.
#
# Usage:
#   ./contrib/seed-kubevirt-networking-demo.sh
#   NAMESPACE=my-ns VM_COUNT=15 ./contrib/seed-kubevirt-networking-demo.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NAMESPACE="${NAMESPACE:-openshift-controller-manager-operator}"
VM_COUNT="${VM_COUNT:-15}"
STORAGE_CLASS="${STORAGE_CLASS:-gp3-csi}"
INSTANCETYPE="${INSTANCETYPE:-u1.medium}"
PREFERENCE="${PREFERENCE:-rhel.10}"
DATASOURCE="${DATASOURCE:-rhel10}"
DATASOURCE_NS="${DATASOURCE_NS:-openshift-virtualization-os-images}"

if ! oc whoami >/dev/null 2>&1; then
  echo "Log in with oc first." >&2
  exit 1
fi

echo "Seeding networking demo resources in namespace: ${NAMESPACE}"

oc get namespace "$NAMESPACE" >/dev/null 2>&1 || oc create namespace "$NAMESPACE"

apply_nad() {
  local name=$1
  if oc get net-attach-def "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "  NAD ${name} already exists"
    oc annotate net-attach-def "$name" -n "$NAMESPACE" \
      networking-console.redhat.com/demo-seed=true --overwrite 2>/dev/null || true
    return
  fi
  echo "  Creating NAD ${name}"
  oc apply -f - <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
  annotations:
    networking-console.redhat.com/demo-seed: "true"
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/linuxBridge
spec:
  config: |-
    {
        "cniVersion": "0.3.1",
        "name": "${name}",
        "type": "bridge",
        "bridge": "linuxBridge",
        "ipam": {},
        "macspoofchk": true,
        "preserveDefaultVlan": false
    }
EOF
}

apply_nad nad-black-landfowl
apply_nad nad-red-falcon
apply_nad nad-blue-heron

# Prefer NADs that already exist in the namespace (demo or pre-existing).
NADS=()
while IFS= read -r nad; do
  [ -n "$nad" ] && NADS+=("$nad")
done < <(oc get net-attach-def -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ ${#NADS[@]} -eq 0 ]; then
  NADS=(nad-black-landfowl nad-red-falcon nad-blue-heron)
fi
echo "  Assigning VMs across ${#NADS[@]} network(s): ${NADS[*]}"

create_vm() {
  local vm_name=$1
  local nad_name=$2
  local nic_name=$3

  if oc get vm "$vm_name" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "  VM ${vm_name} already exists"
    return
  fi

  echo "  Creating VM ${vm_name} (network: ${nad_name})"
  oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${vm_name}
  namespace: ${NAMESPACE}
spec:
  dataVolumeTemplates:
  - metadata:
      name: ${vm_name}-volume
    spec:
      sourceRef:
        kind: DataSource
        name: ${DATASOURCE}
        namespace: ${DATASOURCE_NS}
      storage:
        resources:
          requests:
            storage: 30Gi
        storageClassName: ${STORAGE_CLASS}
  instancetype:
    name: ${INSTANCETYPE}
  preference:
    name: ${PREFERENCE}
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        network.kubevirt.io/headlessService: headless
    spec:
      architecture: amd64
      domain:
        devices:
          autoattachPodInterface: false
          disks:
          - bootOrder: 1
            name: rootdisk
          interfaces:
          - masquerade: {}
            name: default
          - bridge: {}
            model: virtio
            name: ${nic_name}
            state: up
        machine:
          type: pc-q35-rhel9.8.0
        resources: {}
      networks:
      - name: default
        pod: {}
      - multus:
          networkName: ${nad_name}
        name: ${nic_name}
      subdomain: headless
      volumes:
      - dataVolume:
          name: ${vm_name}-volume
        name: rootdisk
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            chpasswd:
              expire: false
            password: demo-networking
            user: rhel
        name: cloudinitdisk
EOF
}

VM_NAMES=(
  amber-fox-01 coral-lynx-02 jade-otter-03 ruby-hawk-04
  silver-wolf-05 bronze-elk-06 copper-bear-07 ivory-seal-08
  onyx-puma-09 pearl-crane-10 slate-viper-11 garnet-lynx-12
  topaz-mink-13 quartz-finch-14 opal-newt-15
)

if [ "$VM_COUNT" -gt 0 ]; then
  for i in $(seq 0 $((VM_COUNT - 1))); do
    vm_name="${VM_NAMES[$i]:-demo-vm-$((i + 1))}"
    nad_name="${NADS[$((i % ${#NADS[@]}))]}"
    nic_name="nic-${vm_name}"
    create_vm "$vm_name" "$nad_name" "$nic_name"
  done
else
  echo "  Skipping VM creation (VM_COUNT=0)"
fi

echo ""
echo "Done. Resources in ${NAMESPACE}:"
oc get net-attach-def -n "$NAMESPACE" 2>/dev/null || true
oc get vm -n "$NAMESPACE" 2>/dev/null || true
