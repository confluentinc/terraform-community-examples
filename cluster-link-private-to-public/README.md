# Cluster Link: Private Enterprise to Public Dedicated Cluster

This example demonstrates how to configure a **source-initiated cluster link** from a private-networked enterprise Kafka cluster to a public dedicated Kafka cluster. This addresses the common scenario where data needs to be replicated from an enterprise cluster behind PrivateLink/VPC peering to a public destination cluster.

## Use Case

This configuration addresses the scenario where:

- **Source cluster**: Enterprise cluster with private networking (e.g., PrivateLink, VPC Peering)
- **Destination cluster**: Public dedicated cluster
- **Requirement**: Data replication from the private source to the public destination

## Why Source-Initiated?

Source-initiated mode is **required** because:

1. The enterprise cluster is behind private networking (PrivateLink)
2. The destination cluster cannot initiate inbound connections to the private source
3. The source cluster must establish the outbound connection to the destination

```
┌─────────────────────────────┐      OUTBOUND      ┌──────────────────────────┐
│  Enterprise Cluster         │  ───────────────>  │  Dedicated Cluster       │
│  (Private Network)          │                    │  (Public Network)        │
│                             │                    │                          │
│  - PrivateLink/VPC Peering  │                    │  - Public Bootstrap      │
│  - Private REST endpoint    │                    │  - Public REST endpoint  │
│  - Source topics            │                    │  - Mirror topics         │
└─────────────────────────────┘                    └──────────────────────────┘
```

## Architecture

The configuration creates:

1. **Source Cluster Resources** (Enterprise, Private):
   - Service account with CloudClusterAdmin role
   - API key for cluster management
   - Source topics to be replicated

2. **Destination Cluster Resources** (Dedicated, Public):
   - Service account with CloudClusterAdmin role
   - API key for cluster management

3. **Cluster Link**:
   - **Destination-side (INBOUND)**: Accepts incoming connection
   - **Source-side (OUTBOUND)**: Initiates connection from private cluster

4. **Mirror Topics**:
   - Read-only replicas on the destination cluster
   - Continuous replication from source topics

## Prerequisites

1. **Existing Clusters**:
   - Enterprise Kafka cluster with private networking configured
   - Public dedicated Kafka cluster

2. **Network Access**:
   - Terraform execution environment must have network access to the **private** enterprise cluster's REST endpoint
   - This typically requires:
     - Running Terraform from within the VPC
     - Using a bastion host or proxy
     - VPN connection to the private network

3. **Permissions**:
   - OrganizationAdmin or equivalent permissions to create service accounts and role bindings

## Testing

This example has been validated with:
- Terraform Provider for Confluent version: **2.62.0**
- Source cluster: Enterprise cluster with PrivateLink networking
- Destination cluster: Dedicated cluster with public networking
- Tested: February 2026

## Important Notes

### Network Considerations

- The source cluster's REST endpoint is **private** and not publicly accessible
- Ensure your Terraform execution environment can reach the private REST endpoint
- The destination cluster's bootstrap and REST endpoints are public

### Security

- API keys inherit CloudClusterAdmin permissions on their respective clusters
- Credentials are marked as sensitive in outputs
- Consider using Terraform state encryption and secure backends

### Mirror Topics

- Mirror topics are **read-only**
- Data flows source topic → mirror topic (one-way)
- Produce to source topics; consume from mirror topics
- Mirror topics are offset-preserving byte-for-byte replicas

## Resources Created

- 2 Service Accounts (source and destination cluster managers)
- 2 Role Bindings (CloudClusterAdmin on each cluster)
- 2 API Keys (one per cluster)
- 3 Kafka Topics (on source cluster)
- 2 Cluster Link resources (destination-inbound + source-outbound)
- 3 Mirror Topics (on destination cluster)

## References

- [Confluent Cluster Linking Documentation](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/cluster-links-cc.html)
- [Cluster Linking Security](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html)
- [Source-Initiated Cluster Links](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/cluster-links-cc.html#source-initiated-cluster-links)
- [Terraform Provider for Confluent Documentation](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)


---

**⚠️ Disclaimer**: This example is community-contributed and provided as-is. Always test in a non-production environment first.
