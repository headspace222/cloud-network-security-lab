# Architecture & Design Rationale

## Why Network Segmentation, Not Just Identity Controls

Every earlier project in this portfolio secured *who* can access a resource
(identity, RBAC) and *what* they can do once authenticated (least-privilege
roles). Neither of those controls whether a resource is reachable from the
public internet in the first place - a misconfigured firewall rule, a
forgotten public access setting, or a leaked SAS token can all bypass
identity controls entirely if the network path exists. Network segmentation
is a genuinely independent layer of defence: even a fully compromised
credential is useless against a resource with no network path to reach it.

## Subnet Design: Application Tier vs. Data Tier

This lab models the most common real-world segmentation pattern: an
application/front-end tier that legitimately needs internet exposure, and a
data tier that should never be directly reachable from outside the network
at all. The app subnet's NSG allows only HTTPS (443) inbound from the
internet - modelling a web application that needs public reachability but
nothing else. The data subnet's NSG allows inbound only from the app
subnet's address range, with an explicit deny rule for internet traffic.

**Why an explicit deny rule, when NSGs already deny by default:** every NSG
has an implicit DenyAllInBound rule at the lowest priority (65500) that
would block internet traffic anyway. The explicit Deny-Internet-Inbound
rule at priority 200 in this lab's data subnet NSG is redundant in a
technical sense, but valuable for a different reason: it makes the security
intent visible and auditable directly in the rule list, rather than relying
on someone knowing to check the implicit default.

## Private Endpoint vs. Service Endpoint vs. Firewall Rules

Azure offers several ways to restrict network access to a PaaS resource
like Storage, each with a materially different security model:

- **Firewall rules (IP allow-listing)**: the resource still has a public
  IP and DNS name; only specific source IPs are permitted to reach it. This
  is the weakest control - the resource remains internet-facing in
  principle.
- **Service Endpoints**: traffic from the specified subnet is routed over
  Azure's backbone network rather than the public internet, but the
  resource still has a public endpoint reachable by others unless firewall
  rules also restrict it.
- **Private Endpoints** (used in this lab): the resource is assigned a
  private IP address directly inside the VNet, and public network access
  can be disabled entirely. The resource genuinely has no public network
  path once public access is disabled, which is what this lab's
  deploy-private-endpoint.ps1 does as its final, most consequential step.

## Why Private DNS Is a Required Step, Not an Optional One

A Private Endpoint gets a private IP address, but the storage account's DNS
name (<account>.blob.core.windows.net) still resolves to its public IP by
default unless something overrides that resolution. Without the Private DNS
Zone (privatelink.blob.core.windows.net) linked to the VNet and populated
via a DNS zone group, anything inside the VNet trying to reach the storage
account by its normal name would still resolve to the (now-disabled) public
endpoint and fail to connect. This is a genuinely common real-world Private
Endpoint misconfiguration: the endpoint itself gets created correctly, but
DNS resolution is overlooked, and the resource becomes unreachable from
anywhere until someone diagnoses the DNS gap specifically.

## A Cross-Project Finding: The Tag Policy Catches Everything

The cost governance lab's enforce-mandatory-tags policy, deployed weeks
earlier in this portfolio, correctly blocked this lab's Private DNS Zone
creation when the deployment script initially omitted tags on that specific
resource - the same pattern that previously caught an Automation Account,
a Function App, and a Log Analytics-linked Workbook in other projects. This
is direct, repeated evidence that a policy deployed once continues
enforcing consistently across every subsequent project in this portfolio,
regardless of which script or tool creates the resource.

## What I'd Add at Enterprise Scale

- Application Security Groups (ASGs), grouping resources by role rather
  than relying purely on subnet-based address ranges in NSG rules
- Azure Firewall or a Network Virtual Appliance, for centralised
  outbound filtering and threat intelligence-based blocking
- Hub-spoke topology, with this VNet as a spoke peered to a central hub
  containing shared services, rather than a single flat VNet
- NSG Flow Logs, feeding into the observability capstone's Log
  Analytics workspace, to see what traffic the NSG rules are actually
  allowing and denying over time
- Private Endpoints for every PaaS resource across this portfolio, not
  just one storage account demonstrated here