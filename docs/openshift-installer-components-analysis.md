# OpenShift Installer Component Architecture Analysis

## Overview

This document analyzes the component relationships within the OpenShift installer ecosystem, using the AWS gp3 throughput feature (CORS-4212) as a concrete example to illustrate the data flow and dependencies between components.

## Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    User/Installation Flow                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: API Definition (openshift/api)                        │
│  - Defines CRD schemas and types                                │
│  - Generates OpenAPI specifications                             │
│  - Provides type definitions for all components                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: Install Config Processing (openshift/installer)       │
│  - Parses and validates install-config.yaml                     │
│  - Generates Machine manifests                                  │
│  - Creates Terraform variables                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: Runtime Validation (openshift/machine-api-operator)    │
│  - Webhook validation for Machine resources                     │
│  - Admission control enforcement                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 4: Cloud Provider Implementation                         │
│  (openshift/machine-api-provider-aws)                           │
│  - Translates Machine specs to cloud API calls                  │
│  - Creates actual infrastructure resources                      │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. openshift/api

**Purpose**: API schema definition and type generation

**Key Responsibilities**:
- Define Kubernetes CRD types (e.g., `EBSBlockDeviceSpec`)
- Generate OpenAPI specifications
- Generate deepcopy methods
- Generate swagger documentation

**Example (gp3 throughput)**:
- File: `machine/v1beta1/types_awsprovider.go`
- Defines: `ThroughputMib *int32` field in `EBSBlockDeviceSpec`
- Generates: OpenAPI schema, deepcopy methods, swagger docs

**Dependencies**: None (base layer)

**Outputs**:
- Go type definitions
- OpenAPI JSON schemas
- Generated code (deepcopy, swagger)

---

### 2. openshift/installer

**Purpose**: Installation configuration processing and manifest generation

**Key Responsibilities**:
- Parse and validate `install-config.yaml`
- Generate Machine manifests
- Generate Terraform variables (for legacy IPI)
- Validate platform-specific constraints

**Key Components**:

#### 2.1 Install Config Schema
- **File**: `data/data/install.openshift.io_installconfigs.yaml`
- **Purpose**: Defines the schema for `install-config.yaml`
- **Example**: Adds `throughput` field to `rootVolume` spec

#### 2.2 Type Definitions
- **File**: `pkg/types/aws/machinepool.go`
- **Purpose**: Go types for install-config processing
- **Example**: `EC2RootVolume.Throughput int64` field

#### 2.3 Validation Logic
- **File**: `pkg/types/aws/validation/machinepool.go`
- **Purpose**: Validates install-config values
- **Example**: `validateThroughput()` checks 125-2000 MiB/s range for gp3

#### 2.4 Machine Manifest Generation
- **Files**: 
  - `pkg/asset/machines/aws/awsmachines.go` (CAPI)
  - `pkg/asset/machines/aws/machines.go` (MAPI)
- **Purpose**: Converts install-config to Machine resources
- **Example**: Maps `throughput` → `throughputMib` in providerSpec

#### 2.5 Terraform Variable Generation
- **File**: `pkg/tfvars/aws/aws.go`
- **Purpose**: Generates Terraform variables for legacy IPI
- **Example**: Adds `aws_master_root_volume_throughput` to tfvars

**Dependencies**: 
- `openshift/api` (for Machine API types)

**Outputs**:
- Machine manifests (`openshift/99_openshift-cluster-api_*.yaml`)
- Terraform variables (`terraform.tfvars.json`)

---

### 3. openshift/machine-api-operator

**Purpose**: Runtime validation and admission control

**Key Responsibilities**:
- Validate Machine resources via webhook
- Enforce business rules at runtime
- Reject invalid Machine configurations

**Key Components**:

#### 3.1 Webhook Validation
- **File**: `pkg/webhooks/machine_webhook.go`
- **Purpose**: Validates Machine resources before creation
- **Example**: Validates `throughputMib` is 125-2000 for gp3 volumes

**Dependencies**:
- `openshift/api` (for type definitions)

**Outputs**:
- Admission decisions (allow/deny)
- Validation error messages

---

### 4. openshift/machine-api-provider-aws

**Purpose**: AWS cloud provider implementation

**Key Responsibilities**:
- Translate Machine specs to AWS EC2 API calls
- Create actual EC2 instances and EBS volumes
- Handle AWS-specific resource management

**Key Components**:

#### 4.1 Block Device Mapping
- **File**: `pkg/actuators/machine/instances.go`
- **Purpose**: Converts Machine providerSpec to AWS API calls
- **Example**: Maps `ThroughputMib` to EC2 `Throughput` parameter

**Dependencies**:
- `openshift/api` (for Machine API types)
- AWS SDK

**Outputs**:
- EC2 instances with configured EBS volumes
- Actual AWS infrastructure resources

---

## Data Flow Example: gp3 Throughput Feature

### Step 1: User Input (install-config.yaml)
```yaml
platform:
  aws:
    defaultMachinePlatform:
      rootVolume:
        type: gp3
        size: 120
        throughput: 500  # User specifies 500 MiB/s
```

### Step 2: Installer Validation
```
install-config.yaml
    ↓
openshift/installer/pkg/types/aws/validation/machinepool.go
    ↓ validateThroughput()
    ✓ Checks: type == "gp3", 125 <= throughput <= 2000
```

### Step 3: Manifest Generation
```
install-config.yaml
    ↓
openshift/installer/pkg/asset/machines/aws/machines.go
    ↓ provider()
    ↓
Machine manifest (openshift/99_openshift-cluster-api_master-machines-0.yaml)
    ↓
providerSpec.blockDevices[].ebs.throughputMib: 500
```

### Step 4: Runtime Validation
```
Machine resource (applied to cluster)
    ↓
openshift/machine-api-operator/pkg/webhooks/machine_webhook.go
    ↓ validateAWS()
    ✓ Checks: throughputMib valid for gp3, range 125-2000
```

### Step 5: AWS Resource Creation
```
Machine resource (validated)
    ↓
openshift/machine-api-provider-aws/pkg/actuators/machine/instances.go
    ↓ getBlockDeviceMappings()
    ↓
AWS EC2 API: CreateVolume(Throughput=500)
    ↓
Actual EBS volume with 500 MiB/s throughput
```

## Component Dependencies

```
openshift/api
    │
    ├───> openshift/installer (imports API types)
    │         │
    │         ├───> Generates Machine manifests
    │         │
    │         └───> Generates Terraform variables
    │
    ├───> openshift/machine-api-operator (imports API types)
    │         │
    │         └───> Validates Machine resources
    │
    └───> openshift/machine-api-provider-aws (imports API types)
              │
              └───> Creates AWS resources
```

## Key Design Patterns

### 1. Schema-Driven Development
- API definitions in `openshift/api` drive all downstream components
- Changes to API types require coordinated updates across all consumers

### 2. Validation at Multiple Layers
- **Install-time**: Installer validates `install-config.yaml`
- **Runtime**: Machine API webhook validates Machine resources
- **Cloud**: AWS API enforces final constraints

### 3. Field Name Translation
- `install-config.yaml`: `throughput` (int64, user-facing)
- Machine API: `throughputMib` (int32, Kubernetes resource)
- AWS API: `Throughput` (int32, cloud provider)

### 4. Backward Compatibility
- All new fields are optional (`+optional` tag)
- Default values handled at each layer
- Missing fields don't break existing installations

## Testing Strategy

Each component has its own test suite:

1. **openshift/api**: Unit tests for type definitions
2. **openshift/installer**: 
   - Unit tests for validation logic
   - Integration tests for manifest generation
3. **openshift/machine-api-operator**: 
   - Webhook validation tests
   - Admission test cases
4. **openshift/machine-api-provider-aws**: 
   - AWS API integration tests
   - End-to-end cluster creation tests

## Common Issues and Solutions

### Issue 1: Field Not Propagating
**Symptom**: Field in install-config doesn't appear in Machine manifests

**Root Causes**:
- Installer not updated to handle new field
- Missing mapping in manifest generation code
- Validation rejecting the field

**Solution**: Check all three layers (installer, validation, generation)

### Issue 2: Validation Failures
**Symptom**: Valid install-config rejected by webhook

**Root Causes**:
- Webhook validation stricter than installer validation
- Field name mismatch (throughput vs throughputMib)
- Type mismatch (int64 vs int32)

**Solution**: Ensure validation rules match across layers

### Issue 3: AWS Resource Mismatch
**Symptom**: Machine created but AWS resource has wrong configuration

**Root Causes**:
- Provider not mapping field to AWS API
- AWS API parameter name different
- Default value overriding user setting

**Solution**: Verify provider implementation maps all fields correctly

## Best Practices

1. **Start with API**: Always define types in `openshift/api` first
2. **Coordinate Changes**: Update all dependent components together
3. **Test Each Layer**: Validate at install-time, runtime, and cloud provider
4. **Document Field Names**: Note translations between layers
5. **Handle Defaults**: Explicitly handle missing/zero values at each layer

## References

- [OpenShift API Conventions](https://github.com/openshift/enhancements/blob/master/dev-guide/api-conventions.md)

