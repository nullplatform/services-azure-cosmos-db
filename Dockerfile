# syntax=docker/dockerfile:1
#
# azure-cosmos-db service worker image, on the lean gRPC worker bridge. The
# bridge dials over gRPC and runs the baked bash entrypoint on each package-exec
# action; this image adds OpenTofu and bakes the service in.
#
# No azure-cli: nothing under scripts/azure/ shells out to `az`. The azurerm
# provider authenticates from the ARM_* environment the worker receives.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:2.0.7

# OpenTofu, pinned. Keep TOFU_VERSION in sync with do_tofu's download fallback,
# which the packaged worker never uses.
ARG TOFU_VERSION=1.13.9
ARG TARGETARCH
RUN set -eu; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64|amd64)  arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
      esac; \
    fi; \
    curl -fsSL -o /tmp/tofu.tar.gz \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${arch}.tar.gz"; \
    tar -xzf /tmp/tofu.tar.gz -C /usr/local/bin tofu; \
    rm -f /tmp/tofu.tar.gz; \
    tofu version

# Bake the service in. --chown so the files belong to the uid this image runs
# as: `np` chmods the action script in place at runtime, and the workflows
# write their tofu output under $SERVICE_PATH/output.
COPY --chown=10001:10001 . /app/pkg
ENV NP_PACKAGE_NAME=azure-cosmos-db \
    NP_SERVICE_PATH=/app/pkg/azure-cosmos-db \
    NP_SCOPE_ENTRYPOINT=/app/pkg/azure-cosmos-db/entrypoint/entrypoint

# Hand HOME to the runtime user: the RUN steps above ran as root with HOME
# already set to /home/app by the base (tofu left ~/.terraform.d there).
RUN chown -R 10001:10001 /home/app

# Drop root for the runtime. Numeric on purpose: k8s admission with
# runAsNonRoot resolves USER to a numeric id to prove it isn't root.
USER 10001:10001
