# rails-cloudflare-origin

## This repository is public: never leak internal information

Read this before writing anything. Anyone on the internet can read every file, commit message, branch name, tag, issue, PR title and body, review comment and CI log in this repository. History is permanent: a force-push or a deleted comment does not remove what was already published, cached or indexed.

The gem must read as a generic library for any Rails app behind Cloudflare. Nothing here may describe the company's own systems. Never write any of the following, anywhere in this repository:

- **Secrets:** tokens, API keys, passwords, credentials, origin secret values, or private URLs.
- **Internal systems:** names of the company's apps, services, hosting apps, databases, domains, hostnames, Cloudflare zones, monitoring projects, internal tools, or infrastructure layout.
- **Internal work:** issue or PR numbers and contents from private repositories, internal plan documents, their paths or their unit IDs, incident details, security measures or weaknesses, or measurements taken on production systems.
- **People and customers:** names, emails, customer or employee data, or business details.
- **Local machine details:** absolute paths from a developer's checkout, usernames, or machine names.

Naming a private repository is fine; quoting or summarizing its contents is not. When a change was motivated by an internal incident, describe the general problem the gem solves ("a forged `Forwarded` header made Rails raise"), never the internal system where it happened.

Do not name the third-party services the company uses (its hosting platform, error tracker or other vendors) in code, comments or docs: describe the role instead ("a proxy server in front of the app", "an error tracker").

Before every commit, push or PR, read the full diff and the message or description you are about to publish with this list in mind. When in doubt, leave it out and ask.

## What this gem is

A Rack middleware, installed by a Railtie, that refuses requests which did not come through Cloudflare and sets the client IP from `CF-Connecting-IP`. See `README.md` for the behavior and the Cloudflare setup it assumes.

## Supported versions

The gem targets the latest Ruby and the latest Rails only. `required_ruby_version` and the `actionpack`/`railties` floors move up with each release; do not add compatibility code for older versions.

## Lint

Standard Ruby (`bundle exec standardrb`, autocorrect with `--fix`). CI and the release workflow run it before the tests.

## Middleware position

The Railtie records `insert_before 0` on `app.config.middleware` from an initializer ordered `after: :load_config_initializers`. Both halves matter: `config.app_middleware` operations are replayed before the application's own, and an earlier initializer records before the app's initializers do, so either change leaves an app's own `insert_before 0` above the middleware. `test/railtie_test.rb` boots `test/dummy` to prove the position; keep it passing.

## Tests

Minitest, run with `bundle exec rake test`. `Rack::MockRequest.env_for` sets no `HTTP_*` header, so a middleware that refuses everything passes every negative case built on it. Each test sets `REMOTE_ADDR` and every header it relies on explicitly.

## Releasing

1. Bump `CloudflareOrigin::VERSION` in a pull request and merge it.
2. On every push to `main`, `release-drafter.yml` updates a draft GitHub release named and tagged `v` plus that version, with notes from the merged pull requests (Dependabot bumps collapsed into one line per dependency or group).
3. Publish the draft. That creates the `v<version>` tag, and the tag push runs `release.yml`, which runs lint and tests and then publishes to RubyGems through trusted publishing in the `release` environment.

Tagging by hand also works; publish the drafted notes for that tag afterwards so the releases page stays complete.

## Gemfile

- **There is no lockfile.** `Gemfile.lock` is gitignored, as usual for a library, so CI resolves every dependency fresh on each run and always tests against the latest releases. A `main` that turns red with no new commit usually means an upstream release changed something.
- **Never version-constrain a gem in the `Gemfile`.** The `Gemfile` lists `gem "name"` only.
- **Constrain only for a very good reason**, and explain the reason in a comment on the same or preceding line.
- **Every gem carries a comment explaining its purpose.**
