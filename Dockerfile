FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
  fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Ensure the state directory exists and has correct permissions
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw /app

# Cloud Run health check timeout can be short, so we ensure the app starts fast.
# We run as root to avoid GCSFuse permission complexities in this environment.
USER root

# Explicitly set the port if not provided by env, though resolveGatewayPort handles it.
ENV PORT=18789

# Start the gateway in the foreground.
# We use the absolute path to node and the script to be safe.
CMD ["node", "/app/dist/index.js", "gateway", "run", "--allow-unconfigured", "--bind", "lan"]
