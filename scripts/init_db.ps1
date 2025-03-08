# Enable verbose output
$VerbosePreference = "Continue"

# Check if sqlx is installed
if (-not (Get-Command sqlx -ErrorAction SilentlyContinue)) {
    Write-Host "Error: sqlx is not installed." -ForegroundColor Red
    Write-Host "Use:" -ForegroundColor Red
    Write-Host "    cargo install --version='~0.8' sqlx-cli --no-default-features --features rustls,postgres" -ForegroundColor Red
    Write-Host "to install it." -ForegroundColor Red
    exit 1
}

# Set default values for parameters if not provided
$DB_PORT = $env:DB_PORT
if (-not $DB_PORT) { $DB_PORT = 5432 }

$SUPERUSER = $env:SUPERUSER
if (-not $SUPERUSER) { $SUPERUSER = 'postgres' }

$SUPERUSER_PWD = $env:SUPERUSER_PWD
if (-not $SUPERUSER_PWD) { $SUPERUSER_PWD = 'password' }

$APP_USER = $env:APP_USER
if (-not $APP_USER) { $APP_USER = 'app' }

$APP_USER_PWD = $env:APP_USER_PWD
if (-not $APP_USER_PWD) { $APP_USER_PWD = 'secret' }

$APP_DB_NAME = $env:APP_DB_NAME
if (-not $APP_DB_NAME) { $APP_DB_NAME = 'newsletter' }

# Allow to skip Docker if a dockerized Postgres database is already running
if (-not $env:SKIP_DOCKER) {
    # Check if a postgres container is running
    $RUNNING_POSTGRES_CONTAINER = docker ps --filter 'name=postgres' --format '{{.ID}}'

    if ($RUNNING_POSTGRES_CONTAINER) {
        Write-Host "There is a postgres container already running, kill it with" -ForegroundColor Yellow
        Write-Host "    docker kill $RUNNING_POSTGRES_CONTAINER" -ForegroundColor Yellow
        exit 1
    }

    # Generate a unique container name
    $CONTAINER_NAME = "postgres_$((Get-Date -UFormat %s))"

    # Launch postgres using Docker
    $CONTAINER_ID = docker run `
        --env POSTGRES_USER=$($SUPERUSER) `
        --env POSTGRES_PASSWORD=$($SUPERUSER_PWD) `
        --health-cmd="pg_isready -U $($SUPERUSER) || exit 1" `
        --health-interval=1s `
        --health-timeout=5s `
        --health-retries=5 `
        --publish "$($DB_PORT):5432" `
        --detach `
        --name $CONTAINER_NAME `
        postgres -N 1000 `

    # Wait until Postgres container is healthy
    while ($true) {
        $healthStatus = docker inspect -f "{{.State.Health.Status}}" $CONTAINER_NAME
        if ($healthStatus -eq 'healthy') {
            break
        }
        Write-Host "Postgres is still unavailable - sleeping" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }

    # Create the application user
    $CREATE_QUERY = "CREATE USER $APP_USER WITH PASSWORD '$APP_USER_PWD';"
    docker exec -it $CONTAINER_NAME psql -U $SUPERUSER -c $CREATE_QUERY

    # Grant create db privileges to the app user
    $GRANT_QUERY = "ALTER USER $APP_USER CREATEDB;"
    docker exec -it $CONTAINER_NAME psql -U $SUPERUSER -c $GRANT_QUERY
}

Write-Host "Postgres is up and running on port $DB_PORT - running migrations now!" -ForegroundColor Green

# Set DATABASE_URL environment variable and run migrations
$DATABASE_URL = "postgres://$($SUPERUSER):$($SUPERUSER_PWD)@host.docker.internal:$($DB_PORT)/$($APP_DB_NAME)"
sqlx database create --database-url $DATABASE_URL
sqlx migrate run --database-url $DATABASE_URL

Write-Host "Postgres has been migrated, ready to go!" -ForegroundColor Green
