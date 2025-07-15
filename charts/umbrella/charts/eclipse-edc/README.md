# Eclipse EDC Connector

This Helm chart deploys an Eclipse EDC (Eclipse Dataspace Connector) built from source, replacing the standard `tx-data-provider` component in the Tractus-X Umbrella.

## Overview

The Custom EDC Connector is based on the [Eclipse EDC Connector](https://github.com/eclipse-edc/Connector) project and provides:

- **Control Plane**: Manages data transfers, policies, and connector configuration
- **Data Plane**: Handles actual data transfer operations
- **Digital Twin Registry**: Manages digital twin registrations
- **Simple Data Backend**: Provides test data endpoints

## Architecture

The chart deploys the following components:

```
Eclipse EDC
├── Control Plane (nuruldhamar/edc-controlplane:latest)
├── Data Plane (nuruldhamar/edc-dataplane:latest)
├── Digital Twin Registry
└── Simple Data Backend
```

## Configuration

### Key Features

- **Built from Source**: Uses Eclipse EDC Docker images built from the Eclipse EDC source code
- **Vault Integration**: Integrates with HashiCorp Vault for secret management
- **Tractus-X Compatibility**: Configured to work with Tractus-X IAM and BDRS
- **Resource Optimized**: Configurable resource limits and requests

### Environment Variables

The control plane and data plane are configured with environment variables that match the docker-compose setup:

#### Control Plane
- `EDC_PARTICIPANT_ID`: BPN identifier (BPNL00000003CRHK)
- `EDC_STORAGE_TYPE`: Storage backend (in-memory)
- `EDC_DSP_CALLBACK_ADDRESS`: DSP protocol endpoint
- `TX_IAM_IATP_CREDENTIALSERVICE_URL`: Tractus-X IAM integration

#### Data Plane
- `EDC_DATAPLANE_API_PUBLIC_BASEURL`: Public API endpoint
- `EDC_DPF_SELECTOR_URL`: Data plane selector URL
- `EDC_TRANSFER_PROXY_TOKEN_SIGNER_PRIVATEKEY_ALIAS`: Token signing configuration

## Usage

### Enable in Umbrella Chart

To use this Eclipse EDC instead of the standard tx-data-provider:

1. Use the `values-eclipse-edc.yaml` file:
   ```bash
   helm install umbrella charts/umbrella -f charts/umbrella/values-eclipse-edc.yaml
   ```

2. Or enable it in your values file:
   ```yaml
   eclipse-edc:
     enabled: true
     controlplane:
       enabled: true
     dataplane:
       enabled: true
   ```

### Access Points

Once deployed, the EDC will be available at:

- **Control Plane**: `http://eclipse-edc-controlplane.tx.test`
- **Data Plane**: `http://eclipse-edc-dataplane.tx.test`
- **DSP Endpoint**: `http://eclipse-edc-controlplane.tx.test/api/v1/dsp`
- **Management API**: `http://eclipse-edc-controlplane.tx.test/management`

## Differences from tx-data-provider

1. **Eclipse EDC Images**: Uses `nuruldhamar/edc-controlplane` and `nuruldhamar/edc-dataplane` instead of the standard Tractus-X connector images
2. **Simplified Configuration**: Direct environment variable configuration instead of complex Tractus-X specific configurations
3. **Source-based**: Built directly from Eclipse EDC source code rather than using pre-built Tractus-X distributions
4. **Resource Efficiency**: Optimized resource allocation for development and testing

## Development

### Building Custom Images

To build your own EDC images:

1. Clone the Eclipse EDC repository:
   ```bash
   git clone https://github.com/eclipse-edc/Connector.git
   cd Connector
   ```

2. Build the control plane:
   ```bash
   docker build -t your-registry/edc-controlplane:latest -f launchers/control-plane/Dockerfile .
   ```

3. Build the data plane:
   ```bash
   docker build -t your-registry/edc-dataplane:latest -f launchers/data-plane/Dockerfile .
   ```

4. Update the values.yaml file with your image references.

## Troubleshooting

### Common Issues

1. **Image Pull Errors**: Ensure the custom images are available in your registry
2. **Vault Connection**: Verify Vault is running and accessible
3. **Resource Limits**: Adjust CPU/memory limits if pods are being OOMKilled

### Logs

Check pod logs for debugging:
```bash
kubectl logs -f deployment/eclipse-edc-controlplane
kubectl logs -f deployment/eclipse-edc-dataplane
```

## License

This chart is part of the Tractus-X project and is licensed under the Apache License 2.0. 