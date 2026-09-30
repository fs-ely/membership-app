.DEFAULT_GOAL := help
.PHONY: help setup install postgres database run stop restart opencode

help:
	@echo "Membership app commands:"
	@echo "  make setup     Install app packages, install/check PostgreSQL, and prepare the database."
	@echo "  make install   Install backend and frontend npm dependencies from their lockfiles."
	@echo "  make postgres  Check for PostgreSQL; on Windows, install PostgreSQL 18 with winget if missing."
	@echo "  make database  Create backend/.env if missing and create the configured PostgreSQL database."
	@echo "  make run       Start the backend and frontend locally (ports 5000 and 3000)."
	@echo "  make stop      Stop the locally running backend and frontend."
	@echo "  make restart   Stop and then start the local backend and frontend."
	@echo "  make opencode  Install OpenCode CLI if missing, then launch it using opencode.json."
	@echo "Prerequisites: Node.js, npm, GNU Make, and OpenCode. PostgreSQL setup needs valid backend/.env credentials."

# Install app dependencies and prepare PostgreSQL without launching OpenCode.
setup: install postgres database

install:
	npm ci --prefix backend
	npm ci --prefix frontend

postgres:
	node scripts/install-postgres.js

database:
	node scripts/setup-database.js

run:
	node scripts/membership-dev.js run

stop:
	node scripts/membership-dev.js stop

restart:
	node scripts/membership-dev.js restart

opencode:
	@if ! command -v opencode >/dev/null 2>&1; then npm install --global opencode-ai@latest || exit 1; fi
	opencode
