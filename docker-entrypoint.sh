#!/bin/sh
set -e

case "$1" in
	rails|rake)
		if [ ! -f './config/database.yml' ]; then
			if [ "$MYSQL_ENABLE" ]; then
				adapter='mysql2'
				host="${MYSQL_HOST:-mysql}"
				port="${MYSQL_PORT:-3306}"
				username="${MYSQL_USER:-root}"
				password="${MYSQL_PASSWORD:-$MYSQL_ROOT_PASSWORD}"
				database="${MYSQL_DATABASE:-${MYSQL_USER:-redmine}}"
				encoding=
			else
				echo >&2 'warning: missing MYSQL_ENABLE environment variables'
				echo >&2 '  Did you forget to set MYSQL_ENABLE=true ?'
				echo >&2
				echo >&2 '*** Using sqlite3 as fallback. ***'
				
				adapter='sqlite3'
				host='localhost'
				username='redmine'
				database='sqlite/redmine.db'
				encoding=utf8
				
				mkdir -p "$(dirname "$database")"
				chown -R redmine:redmine "$(dirname "$database")"
			fi
			
			cat > './config/database.yml' <<-YML
				$RAILS_ENV:
				  adapter: $adapter
				  database: $database
				  host: $host
				  username: $username
				  password: "$password"
				  encoding: $encoding
				  port: $port
			YML
		fi

		if [ ! -f './config/configuration.yml' ]; then
			if [ "$SMTP_USER" ]; then
				smtp_user="${SMTP_USER}"
				smtp_password="${SMTP_PASSWORD}"
				smtp_host="${SMTP_HOST}"
				smtp_port="${SMTP_PORT}"

				if [ "$REDMINE_DOMAIN" ]; then
					redmine_domain="${REDMINE_DOMAIN}"
				fi

				cat > './config/configuration.yml' <<-YML
				$RAILS_ENV:
					  email_delivery:
					    delivery_method: :smtp
					    smtp_settings:
					      enable_starttls_auto: true
					      address: "$smtp_host"
					      port: "$smtp_port"
					      domain: "$redmine_domain"
					      authentication: :plain
					      user_name: "$smtp_user"
					      password: "$smtp_password"
				YML
			fi
		fi
		
		# ensure the right database adapter is active in the Gemfile.lock
		bundle install --without development test
		
		if [ ! -s config/secrets.yml ]; then
			if [ "$REDMINE_SECRET_KEY_BASE" ]; then
				cat > 'config/secrets.yml' <<-YML
					$RAILS_ENV:
					  secret_key_base: "$REDMINE_SECRET_KEY_BASE"
				YML
			elif [ ! -f /usr/src/redmine/config/initializers/secret_token.rb ]; then
				rake generate_secret_token
			fi
		fi
		if [ "$1" != 'rake' -a -z "$REDMINE_NO_DB_MIGRATE" ]; then
			gosu redmine rake db:migrate
		fi
		
		chown -R redmine:redmine files log public/plugin_assets
		
		# remove PID file to enable restarting the container
		rm -f /usr/src/redmine/tmp/pids/server.pid
		
		set -- gosu redmine "$@"
		;;
esac

exec "$@"
