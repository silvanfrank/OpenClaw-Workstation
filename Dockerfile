# This gives you a full Linux desktop where:
# - OpenClaw runs as a background service on port 18789
# - Any dev server it spins up is accessible at localhost:PORT
# - You can use Firefox to access everything

FROM lscr.io/linuxserver/webtop:ubuntu-xfce

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3 \
    unzip \
    jq \
    file \
    && rm -rf /var/lib/apt/lists/*

# Install Homebrew (Non-interactive)
# We install to the standard location /home/linuxbrew/.linuxbrew
RUN mkdir -p /home/linuxbrew/.linuxbrew && \
    curl -fsSL https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C /home/linuxbrew/.linuxbrew

# Set up permissions for the default user (abc:1000) used by linuxserver images
# We make it world-writable or owned by 1000 so the user can use brew
RUN chown -R 1000:1000 /home/linuxbrew/.linuxbrew

# Add Homebrew to PATH for all users
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
RUN brew --version

# Install Node.js 22 (required for OpenClaw)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 
RUN apt-get install -y nodejs

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Build OpenClaw from source
WORKDIR /opt/openclaw
# Clone first to fail fast if network is down
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git .

# Install dependencies with increased memory limit for build
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm install --frozen-lockfile

# Build with error handling
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build || (echo "Build failed" && exit 1)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build || (echo "UI Build failed" && exit 1)

# Remove power manager to prevent dbus permission errors in unprivileged container
RUN apt-get remove -y xfce4-power-manager || true


ENV NODE_ENV=production
# Persisted upload/download target for Selkies sidebar file manager.
# Can be overridden in Coolify.
ENV FILE_MANAGER_PATH=/config/uploads
# Selkies desktop-stream tuning defaults (override in Coolify env vars if needed)
ENV START_DOCKER=false
ENV SELKIES_MANUAL_WIDTH=1600
ENV SELKIES_MANUAL_HEIGHT=900
ENV MAX_RESOLUTION=1920x1080
ENV SELKIES_FRAMERATE=24
ENV SELKIES_H264_CRF=30

# Expose ports
# 3000 = Webtop desktop UI
# 18789 = OpenClaw Gateway
EXPOSE 3000 18789

# Health check (mirrors OpenClaw/Dockerfile)
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD curl -f http://localhost:18789/health || exit 1

# Add OpenClaw as an S6 service
COPY openclaw-run /etc/services.d/openclaw/run
RUN chmod +x /etc/services.d/openclaw/run

# Add Auth Helper (maps WORKSTATION_PASSWORD -> system password)
# We run this EARLY (01-) in standard init.d so that '30-config' (etc) see the env var
COPY workstation-auth /etc/cont-init.d/01-workstation-auth
RUN chmod +x /etc/cont-init.d/01-workstation-auth

# Add File Manager Path helper (ensures upload path exists and is writable on every start)
COPY workstation-filemanager-path /etc/cont-init.d/02-workstation-filemanager-path
RUN chmod +x /etc/cont-init.d/02-workstation-filemanager-path


# Webtop handles the main entrypoint via s6-overlay
# Our script runs via custom-cont-init.d to start OpenClaw in background
