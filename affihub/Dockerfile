# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t affihub .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name affihub affihub

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl ffmpeg fonts-noto-core libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) asset="yt-dlp_linux"; checksum="58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a" ;; \
      arm64) asset="yt-dlp_linux_aarch64"; checksum="b16e4dab368a816cd05d477d698a605a6ae87ccee1c8ffd38fa21d7254141fcc" ;; \
      *) echo "Unsupported yt-dlp target architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl --fail --location --silent --show-error \
      "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/$asset" \
      --output /usr/local/bin/yt-dlp && \
    echo "$checksum  /usr/local/bin/yt-dlp" | sha256sum --check --status && \
    chmod 0755 /usr/local/bin/yt-dlp && \
    test "$(/usr/local/bin/yt-dlp --version)" = "2026.08.19"

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    SOLID_QUEUE_IN_PUMA="true" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Resolve Tailwind plugins in a dedicated Node package stage.
FROM docker.io/library/node:22-slim AS node_packages
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
COPY --from=node_packages /app/node_modules ./node_modules

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
