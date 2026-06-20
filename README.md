# Arbiter

Arbiter is a policy-aware access gateway for Agentic RAG systems.

It ensures that AI agents can only retrieve, use, and cite data the current user is allowed to access.

## Current Scope

This repository is initialized as a Phoenix/Ecto application for the MVP described in `ARBITER_DIRECTION.md`.

The first implementation slice is the domain skeleton:

- Tenants, users, groups, and memberships
- Documents and chunks
- Policies and policy decisions
- Agent runs
- Retrieval traces

To start your Phoenix server:

* Run `docker compose up -d db` to start the local PostgreSQL dependency
* Run `mix setup` to install dependencies, create the database, and migrate it
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

The default local database URL is `ecto://postgres:postgres@localhost:55432/arbiter_dev`.
Override it with `DATABASE_URL`; tests can use `TEST_DATABASE_URL`.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
