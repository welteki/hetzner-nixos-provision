# Terraform files

## Setup pg backend on Heroku

```
# Pick a unique app name

export APP_NAME=hc-nixos-provision

# Create the database

heroku create $APP_NAME

heroku addons:create heroku-postgresql:hobby-dev --app $APP_NAME

# Initialize Terraform with the database credentials

export DATABASE_URL=`heroku config:get DATABASE_URL --app $APP_NAME`

terraform init -backend-config="conn_str=$DATABASE_URL"

```
