# Azure Cosmos DB Service

Nullplatform **dependency service** that creates a SQL database, with its
containers, inside an existing Azure Cosmos DB account. Each application link
grants the linked scope's managed identity a Cosmos SQL role on the containers
it selects, so apps authenticate with Azure AD and never see an account key.

The service lives under [`azure-cosmos-db/`](./azure-cosmos-db).

## What It Does

- Creates a Cosmos DB SQL database named after the service, with one container
  per entry of the `containers` attribute (name + partition key), via OpenTofu
- On link, assigns the built-in Cosmos SQL roles (Data Reader / Data
  Contributor) to the managed identity of the Azure Web App the linked scope
  deploys to, on the selected containers or on the whole database
- Exposes the account endpoint, the database name and the containers as the
  service results, and the granted containers as the link results
- Keeps the OpenTofu state in an Azure Storage container when
  `AZURE_TFSTATE_STORAGE_ACCOUNT` / `AZURE_TFSTATE_CONTAINER` are set
  (per-service key `cosmos-db/<service_id>/`), locally otherwise
- Ships as an OCI worker image: the channel routes `package-exec` to a worker
  built from this repository's [`Dockerfile`](./Dockerfile), with OpenTofu
  baked in

The service never creates a Cosmos DB account: the account is a prerequisite,
named on the worker (see [Install in your organization](#install-in-your-organization)).

## Repository Layout

```
.
├── azure-cosmos-db/
│   ├── specs/
│   │   ├── service-spec.json.tpl   # Service schema (the containers to create)
│   │   └── links/connect.json.tpl  # Link schema (containers + access level, or all)
│   ├── publish/                    # publishes the service as a package (release workflow only)
│   ├── deployment/                 # OpenTofu module: the database and its containers
│   ├── permissions/                # OpenTofu module: the role assignments of a link
│   ├── workflows/azure/            # Workflow YAMLs (create/update/delete/read/link/unlink)
│   ├── scripts/azure/              # context resolution, tofu execution, app name
│   ├── entrypoint/                 # entrypoint/service/link (agent entrypoint)
│   ├── examples/                   # fixtures and dry-run scripts
│   └── values.yaml                 # Static config, optional — every key may stay empty
├── Dockerfile                      # worker image: worker-bridge + OpenTofu + this service
└── README.md
```

## Service Configuration Parameters

Exposed in the nullplatform UI when creating the service:

| Parameter | Type | Description |
|---|---|---|
| `containers` | array, at least one | The containers of the database: `containerName` and `partitionKey` (a path such as `/customerId`) each |

The database name is the service slug with dashes replaced by underscores.
`update` is a no-op today: containers are set at creation.

## Link Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `allContainers` | boolean | `false` | Grant the role on the whole database instead of per container |
| `target` | array | | Per container: `container` (one of the service's) and `accessLevel` (`read`, `write` or `read/write`) |

The link resolves the Azure Web App of the linked scope by the name the Azure
App Service scope derives (`<namespace>-<application>-<scope>-<scope id>`) and
grants the roles to that app's system-assigned managed identity. **Links work
for scopes of the Azure App Service type only.**

## Requirements

### nullplatform prerequisites

- An agent with worker orchestration enabled and `np-azure-cosmos-db` in the
  agent module's `worker_orchestrated_packages`
- The worker needs the Azure environment (`ARM_*`, `AZURE_SUBSCRIPTION_ID`)
  and the Cosmos DB account to use (`COSMOS_ACCOUNT_NAME`,
  `COSMOS_RESOURCE_GROUP`); see [Install in your organization](#install-in-your-organization)
- An existing Cosmos DB account (SQL API) in that resource group

### Azure permissions

The identity running this service — the agent's service principal or managed
identity — needs:

| On | Role or permission | For |
|---|---|---|
| The Cosmos DB account | `DocumentDB Account Contributor` | creating and deleting databases and containers |
| The Cosmos DB account | `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/*` | the role assignments of the links (`Cosmos DB Operator` does not include them) |
| The Web Apps' resource group | `Reader` | resolving the linked app's managed identity |
| The tfstate Storage Account, when used | `Storage Blob Data Contributor` | reading and writing state |

### Runtime dependencies

- **OpenTofu** — baked into the worker image at the version pinned by the
  Dockerfile's `TOFU_VERSION`. `do_tofu` keeps a download fallback for agents
  without it, which the packaged worker never uses.
- `bash`, `jq`, `np` and `curl` ship in the `worker-bridge` base image. No
  `azure-cli`: nothing under `scripts/azure/` shells out to `az`.

## Install in your organization

The service is published once as the package `np-azure-cosmos-db` (specification "Azure Cosmos DB"), visible to every organization. You do not copy its specs: you install the package and use it read-only.

How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this service.

Installing it touches two layers: the agent, which runs the worker with the Azure environment and the account to use, and the nullplatform layer. There is no infrastructure module: grant the roles in [Requirements](#requirements) directly.

| Layer | What | Module |
|---|---|---|
| agent (Helm) | The package in `worker_orchestrated_packages`, and the environment its worker reads | tofu-modules' [`nullplatform/agent`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/agent) |
| nullplatform (nullplatform API key) | The installation of the package and the agent channel | tofu-modules' `service_package_installation` |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/services-azure-cosmos-db/releases)) and install its version.

```hcl
# ── agent ────────────────────────────────────────────────────────────
# In tofu-modules' nullplatform/agent:
  worker_orchestrated_packages = ["np-azure-cosmos-db"]

  worker = {
    patches = [{
      target = { package = "np-azure-cosmos-db" }
      merge = {
        spec = {
          containers = [{
            name    = "worker"
            envFrom = [{ secretRef = { name = "<agent-secret>" } }] # the ARM_* credentials
            env = [
              { name = "COSMOS_ACCOUNT_NAME",     value = "<cosmos account>" },
              { name = "COSMOS_RESOURCE_GROUP",   value = "<its resource group>" },
              # Where the Azure Web Apps of the linked scopes live; defaults to
              # the account's resource group.
              { name = "COSMOS_APP_RESOURCE_GROUP", value = "<web apps resource group>" },
              # Optional: OpenTofu state in a Storage container instead of the worker's disk.
              { name = "AZURE_TFSTATE_STORAGE_ACCOUNT", value = "<tfstate account>" },
              { name = "AZURE_TFSTATE_CONTAINER",       value = "<tfstate container>" },
              { name = "AZURE_TFSTATE_RESOURCE_GROUP",  value = "<tfstate resource group>" },
            ]
          }]
        }
      }
    }]
  }

# ── nullplatform layer ───────────────────────────────────────────────
# For a service the installation is the whole nullplatform side, channel included.
module "azure_cosmos_db" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_package_installation?ref=v9.16.0"

  nrn                  = var.nrn
  package_slug         = "np-azure-cosmos-db"
  package_version      = "X.Y.Z" # the same release, without the v
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}
# Keeping channels in a separate bindings layer instead? Use
# nullplatform/package_installation here and service_definition_agent_association
# there, with package_slug = "np-azure-cosmos-db".
```

The `envFrom` is required: the agent module injects the Azure environment only into the `containers` package's worker, so any other package's worker starts with none of it. `AZURE_SUBSCRIPTION_ID` (or `ARM_SUBSCRIPTION_ID`) comes with it.

To upgrade, move `package_version` to the new release. See tofu-modules' [`service_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/service_package_installation) for its inputs and outputs.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors` and with `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries`; the rest is in [Requirements](#requirements).

## How the package is published

Every release publishes a new revision of the package from this repository, in the same run that pushes the worker image ([`.github/workflows/release.yml`](./.github/workflows/release.yml)): the `publish-package` job applies [`azure-cosmos-db/publish`](./azure-cosmos-db/publish), a stack on tofu-modules' `service_package_publish`, which pins this tag's specs and the image by digest. The package version is the release tag, as for the image. The stack keeps its state where the organization secrets `PACKAGE_STATE_AWS_ACCOUNT_ID`, `PACKAGE_TFSTATE_BUCKET` and `PACKAGE_TFSTATE_REGION` point; the state role is `github-actions-<repository>-package-state` in that account, by convention.

## Important considerations

### The account is a prerequisite

The service manages databases and containers inside an account it does not
create. The account and its resource group are named on the worker
(`COSMOS_ACCOUNT_NAME`, `COSMOS_RESOURCE_GROUP`); a value pinned in
`values.yaml` wins over the environment.

### Delete destroys the database

`delete` destroys the database and every container in it, with their data.
There is no final backup.

### Links need an Azure App Service scope

The link grants roles to the managed identity of the Web App named after the
linked scope. A scope of another type (Containers on AKS, for instance) has no
such app, and the link fails to resolve it.

### Local state without a tfstate container

Without `AZURE_TFSTATE_STORAGE_ACCOUNT` and `AZURE_TFSTATE_CONTAINER` the
OpenTofu state stays on the worker's disk, under `output/`, and is lost when
the worker pod goes. Set them for anything beyond a trial.

## Testing

[`azure-cosmos-db/examples/dry-run-service-spec.sh`](./azure-cosmos-db/examples/dry-run-service-spec.sh)
runs `build_context` on a recorded notification without touching Azure;
`full-test-service-spec.sh` applies the deployment module for real against the
subscription of your environment.
