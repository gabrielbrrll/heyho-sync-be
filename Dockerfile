# Dockerfile

# Use the official Ruby image
FROM ruby:3.2.0-slim-bullseye AS base

# Set environment variables
ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    LANG=C.UTF-8

# Set up dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libpq-dev \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# --- Build Stage ---
FROM base AS build

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# --- Final Stage ---
FROM base

# Copy installed gems
COPY --from=build /usr/local/bundle /usr/local/bundle

# Copy application code
COPY . .

# Copy and set permissions for the entrypoint script
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# Expose port 3000 and start the Rails server
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

