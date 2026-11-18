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

Publishing the release draft is the whole release: there is no version-bump commit, no local step and no API key.

1. Every push to `main` updates a draft GitHub release from the merged pull request titles. Its version bumps the highest published release: a pull request labelled `major` or `minor` bumps that part, and any other pull request bumps the patch.
2. Publish the draft. Its `vX.Y.Z` tag runs `release.yml`, which runs `ci.yml` on the tagged commit and, only if that passes, stamps the version into `lib/cloudflare_origin/version.rb` with `bin/stamp-version`, builds the gem and pushes it through RubyGems trusted publishing in the `release` environment.

`lib/cloudflare_origin/version.rb` holds the placeholder `0.0.1.dev` and is never bumped by hand.

Release Drafter skips prereleases: drafts are never prereleases, and a published prerelease is ignored when it picks the release to bump from.

The trusted publisher on rubygems.org must name workflow `release.yml` and environment `release`; a blank environment field accepts any environment.

### Recovering from a failed publish

Release tags are never moved or deleted. If the `Release` run fails, in `ci` or in `publish`, fix the cause and re-run its failed jobs on the same tag. If that tag cannot be released, because the tagged commit is broken or the run is too old to re-run, leave its tag and release in place and ship the fix as the next version. Before publishing that next draft, regenerate its notes by running the `Release Drafter` workflow on `main` from the Actions tab, and add back any changes the failed release never shipped.

## Gemfile

- **There is no lockfile.** `Gemfile.lock` is gitignored, as usual for a library, so CI resolves every dependency fresh on each run and always tests against the latest releases. A `main` that turns red with no new commit usually means an upstream release changed something.
- **Never version-constrain a gem in the `Gemfile`.** The `Gemfile` lists `gem "name"` only.
- **Constrain only for a very good reason**, and explain the reason in a comment on the same or preceding line.
- **Every gem carries a comment explaining its purpose.**
