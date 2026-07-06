#!/bin/bash

echo "🚀 Starting NexoPOS on Railway..."

# Ensure storage directories exist
mkdir -p storage/framework/cache/data
mkdir -p storage/framework/sessions
mkdir -p storage/framework/views
mkdir -p storage/logs

# Generate APP_KEY if not set
if grep -q "APP_KEY=$" .env || [ -z "$APP_KEY" ]; then
    echo "🔑 Generating APP_KEY..."
    php artisan key:generate --force --no-interaction
fi

# Create storage symlink
php artisan storage:link --force --no-interaction 2>/dev/null || true

# Wait for database to be ready
echo "⏳ Waiting for database..."
for i in $(seq 1 30); do
    php artisan tinker --execute 'try { DB::connection()->getPdo(); echo "ok"; } catch(\Exception \$e) { echo "waiting"; }' 2>/dev/null | grep -q "ok" && { echo "   Database ready!"; break; }
    echo "   Attempt $i/30..."
    sleep 2
done

# Run database migrations
echo "📦 Running database migrations..."
php artisan migrate --force --no-interaction

# Parse DATABASE_URL for Railway PostgreSQL and expose individual vars
# This is needed because NexoPOS SetupCommand checks for DB_HOST, DB_DATABASE, etc.
if [ -n "$DATABASE_URL" ]; then
    echo "🔧 Parsing DATABASE_URL..."
    export DB_CONNECTION=pgsql
    # Extract database URL components (format: postgresql://user:password@host:port/database)
    DB_URL_REGEX='^postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$'
    if [[ "$DATABASE_URL" =~ $DB_URL_REGEX ]]; then
        export DB_USERNAME="${BASH_REMATCH[1]}"
        export DB_PASSWORD="${BASH_REMATCH[2]}"
        export DB_HOST="${BASH_REMATCH[3]}"
        export DB_PORT="${BASH_REMATCH[4]}"
        export DB_DATABASE="${BASH_REMATCH[5]}"
        echo "   Database host: $DB_HOST"
    fi
fi

# Run NexoPOS setup if not already installed
echo "🔧 Checking NexoPOS installation..."
php artisan tinker --execute 'echo App\Services\Helper::installed() ? "installed" : "not installed";' 2>/dev/null | grep -q "not installed"
if [ $? -eq 0 ]; then
    echo "⚙️  Running NexoPOS setup..."
    php artisan ns:setup \
        --store_name="${NS_STORE_NAME:-My Store}" \
        --admin_username="${NS_ADMIN_USERNAME:-admin}" \
        --admin_email="${NS_ADMIN_EMAIL:-admin@nexopos.com}" \
        --admin_password="${NS_ADMIN_PASSWORD:-password}" \
        --language="${NS_LANGUAGE:-en}"
fi

# Sync modules
echo "🔗 Creating module symlinks..."
php artisan modules:symlink --no-interaction 2>/dev/null || true

# Cache config for production
echo "⚡ Optimizing..."
php artisan config:cache --no-interaction 2>/dev/null || true
php artisan route:cache --no-interaction 2>/dev/null || true
php artisan view:cache --no-interaction 2>/dev/null || true

# Start the server
echo "✅ NexoPOS is ready! Starting server on port ${PORT:-8080}..."
php artisan serve --host=0.0.0.0 --port=${PORT:-8080}
