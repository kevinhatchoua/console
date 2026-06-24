# OpenShift Networking UX — Delivered Features

**Jira:** [HPUX-1766](https://redhat.atlassian.net/browse/HPUX-1766), [HPUX-1767](https://redhat.atlassian.net/browse/HPUX-1767)  
**Author:** Kevin Hatchoua  
**Date:** June 24, 2026  
**Status:** Prototype delivered — screenshots pending

---

## Executive summary

This prototype delivers bidirectional navigation between OpenShift networking resources (NetworkAttachmentDefinitions and User Defined Networks) and the Virtual Machines that consume them. Users can now discover attached VMs from a network detail page, attach or remove VMs, and navigate from VM networking views directly to the underlying network resource — all using established OpenShift Console and PatternFly patterns.

---

## Background

Cluster administrators and platform engineers managing KubeVirt secondary networks need to answer two related questions:

1. **From a network:** Which VMs are attached to this NAD or UDN?
2. **From a VM:** Which network resource does this interface use, and how do I get there quickly?

Previously, these relationships were implicit in VM specs and required manual YAML inspection or kubectl queries. The delivered work surfaces these relationships in the console UI with actionable navigation and management flows.

---

## Features delivered

### 1. Virtual machines tab on network detail pages (HPUX-1767)

**Repository:** networking-console-plugin

Network detail pages for **NetworkAttachmentDefinitions (NADs)** and **User Defined Networks (UDNs)** now include a **Virtual machines** tab alongside Details and YAML.

#### Tab count badge

- A read-only PatternFly badge displays the count of attached VMs inline with the tab label.
- Badge is centered vertically with the tab title using shared co-tab-count-badge styling.
- Console core horizontal nav was updated to render tab badges inline with labels (previously rendered as tab actions).

**[SCREENSHOT: NAD detail page showing Virtual machines tab with count badge]**

#### Attached VMs list

The Virtual machines tab shows a sortable, filterable table with columns: Name, Namespace, Status, Interface, and Actions.

**[SCREENSHOT: Virtual machines tab — populated list view]**

#### Empty state

When no VMs are attached, an empty state explains the situation and provides a primary Add virtual machines action.

**[SCREENSHOT: Virtual machines tab — empty state]**

#### Add virtual machines

- Primary toolbar button opens a modal to search and multi-select VMs in the namespace.
- Selected VMs are attached to the network by patching their network interface spec.
- Already-attached VMs are excluded from the available list.

**[SCREENSHOT: Add virtual machines modal]**

#### Remove from network

- Row action Remove from network opens a confirmation modal.
- On confirm, the network interface is removed from the VM spec.

**[SCREENSHOT: Remove from network confirmation modal]**

#### Supported resource kinds

| Resource | Virtual machines tab |
|----------|---------------------|
| NetworkAttachmentDefinition | Yes |
| UserDefinedNetwork | Yes |
| ClusterUserDefinedNetwork | Yes (cluster-scoped VM list) |

---

### 2. Clickable network links from VM views (HPUX-1766)

**Repository:** kubevirt-plugin

Secondary network names in VM networking views are now direct PatternFly-blue resource links that navigate to the corresponding network detail page. Tooltips on network names were removed in favor of direct navigation.

#### Where it applies

| Location | Behavior |
|----------|----------|
| VM Overview → Network interfaces | Secondary network names link to NAD/UDN/CUDN detail |
| VM Configuration → Network tab → Network column | Secondary network names link to resource detail |
| Pod networking | Remains plain text (not a link) |

#### Link resolution

The VMNetworkResourceLink component resolves multus network references to NetworkAttachmentDefinition, UserDefinedNetwork, or ClusterUserDefinedNetwork and navigates to networking-console-plugin detail routes using standard co-resource-item__resource-name styling.

**[SCREENSHOT: VM Configuration → Network tab with blue network links]**

**[SCREENSHOT: VM Overview → Network interfaces with blue network links]**

---

### 3. Console platform support

**Repository:** openshift-networking (OpenShift Console fork)

#### Horizontal nav tab badges

- Updated horizontal-nav.tsx to render optional tab badge content inline with the tab title.
- Added co-tab-title-with-count and co-tab-count-badge SCSS for consistent badge alignment.

#### Local development infrastructure

| Script | Purpose |
|--------|---------|
| contrib/local-console-with-cluster-plugins.sh | Runs Bridge with networking-console-plugin, kubevirt-plugin, and other cluster plugins |
| contrib/local-console-daemon.sh | Auto-recovering daemon for persistent local console sessions |
| contrib/seed-kubevirt-networking-demo.sh | Seeds demo NADs and VMs for local testing (idempotent) |

---

## User flows

### Flow A: Network → VM discovery

Networking → NetworkAttachmentDefinitions → [select NAD] → Virtual machines tab (badge shows count) → Browse attached VMs → Add virtual machines OR Remove from network

### Flow B: VM → Network navigation

Virtualization → VirtualMachines → [select VM] → Configuration → Network tab → Click secondary network name (PF blue link) → Network detail page

---

## Technical notes

### Key components (networking-console-plugin)

- NetworkAttachedVirtualMachinesTab — main tab content
- AddVirtualMachinesModal / RemoveVirtualMachineFromNetworkModal — attach/detach flows
- TabCountBadge / getTabCountBadge — tab count rendering
- useAttachedVirtualMachines — discovers VMs via network spec cross-reference

### Key components (kubevirt-plugin)

- VMNetworkResourceLink — resolves and links to network resources
- useVMNetworkResourceTarget — multus reference parsing and kind detection

---

## Repositories and commits

| Repository | Key commits |
|------------|-------------|
| networking-console-plugin | 35b875e network-to-VM navigation; c1b7350 VM tab with count badge |
| kubevirt-plugin | e1b23e2 clickable PF-blue network links |
| openshift-networking | 4937013 tab count badges + demo seeding; 868a92a local console hardening |

---

## Out of scope / follow-up

- Production-ready RBAC review for attach/remove actions
- E2E test coverage for network ↔ VM flows
- i18n review for new strings across all locales
- Tree view navigation pattern (if still planned under HPUX-1767)
- Upstream PRs to openshift/networking-console-plugin and kubevirt-ui/kubevirt-plugin

---

## Screenshots checklist

1. [ ] NAD detail — Virtual machines tab with badge
2. [ ] Virtual machines tab — populated list
3. [ ] Virtual machines tab — empty state
4. [ ] Add virtual machines modal
5. [ ] Remove from network modal
6. [ ] VM Configuration → Network tab with links
7. [ ] VM Overview → Network interfaces with links
