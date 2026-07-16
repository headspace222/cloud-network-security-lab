# Architecture Diagram

```mermaid
flowchart TB
    Internet((Internet))

    subgraph VNet["VNet 10.20.0.0/16"]
        direction TB
        subgraph AppSubnet["App Subnet - 10.20.1.0/24"]
            NSGApp[NSG: Allow HTTPS 443 inbound from Internet only]
        end
        subgraph DataSubnet["Data Subnet - 10.20.2.0/24"]
            NSGData[NSG: Allow from App Subnet only. Explicit Deny from Internet]
            PE[Private Endpoint]
        end
    end

    Storage[(Storage Account - PublicNetworkAccess Disabled)]
    DNS[Private DNS Zone - privatelink.blob.core.windows.net]

    Internet -->|HTTPS 443 only| NSGApp
    NSGApp -.-> AppSubnet
    AppSubnet -->|allowed| NSGData
    Internet -.->|explicitly denied| NSGData
    NSGData -.-> DataSubnet
    PE -->|private IP connection| Storage
    DNS -.resolves storage name to private IP.-> PE
    Internet -.-x|no public path exists| Storage

    style Internet fill:#fce8e6,stroke:#d93025
    style VNet fill:#e8f4fd,stroke:#1a73e8
    style Storage fill:#e6f4ea,stroke:#188038
    style DNS fill:#fef7e0,stroke:#f9ab00
```

## Reading This Diagram

**The app subnet** accepts only HTTPS traffic from the internet - modelling
a legitimate public-facing web tier.

**The data subnet** accepts traffic only from the app subnet, with an
explicit deny rule for direct internet access, stating the security intent
plainly rather than relying on NSGs' implicit default deny.

**The storage account**, once PublicNetworkAccess is disabled, has no
public network path at all - the red dashed line with an X shows that
direct internet-to-storage connectivity, which existed before this lab's
build, no longer exists after it. The only path in is through the Private
Endpoint, resolvable only via the Private DNS zone linked to this specific
VNet.