# rails-cloudflare-origin

For a Rails app served through Cloudflare: refuses requests that did not come through Cloudflare, and sets the client IP from `CF-Connecting-IP` on those that did.

Behind Cloudflare and a proxy server in front of the app, `request.remote_ip` tends to return the proxy's own address for every request, because the proxy appends itself to `X-Forwarded-For` and Rails does not trust it. Trusting the proxy and Cloudflare's IP ranges instead means a list to keep current. This gem takes a different route: once a request has proved it came through Cloudflare, the address Cloudflare put in `CF-Connecting-IP` is the visitor.

## Installation

```ruby
gem "rails-cloudflare-origin"
```

A Railtie installs the middleware at the top of the stack, above anything the app inserts with `insert_before 0` from an initializer or an environment file, and above Rails' own `HostAuthorization` and `ActionDispatch::SSL`. Nothing else is needed in the app.

## What it does on each request

1. Removes `Forwarded`, `Client-IP`, `X-Forwarded-For`, `X-Real-IP` and `X-Forwarded-Host`. A visitor can send any of these, and conflicting values make Rails raise `ActionDispatch::RemoteIp::IpSpoofAttackError`, which surfaces as a 500. `X-Forwarded-Proto` and `X-Forwarded-Port` stay.
2. Takes the `X-Origin-Secret` header out of the request, so it never reaches the app, its logs, or an error tracker.
3. Lets a `GET` or `HEAD` of exactly `/up` through without the secret when it carries no `CF-Ray` header. This is the platform's health check, which reaches the app directly instead of through Cloudflare. A `/up` that came through Cloudflare still needs the secret.
4. Answers anything else without a matching secret with a `403` and `cache-control: no-store`.
5. Sets `REMOTE_ADDR` to `CF-Connecting-IP`, so `request.ip` and `request.remote_ip` both return the visitor. A request that carries the secret but no `CF-Connecting-IP`, or one that is not an IP address, raises `CloudflareOrigin::InvalidClientIpError`. Cloudflare always sends that header, so its absence means a zone setting changed, and an error is easier to notice than every visitor quietly sharing one address. The middleware runs above Rails' own error handling, so it reports the error to `Rails.error` itself before raising: any error tracker subscribed to `Rails.error` receives it, and the request ends as a 500 from the app server.

## What it trusts

- **The origin secret.** A request carrying it came through your Cloudflare zone, because only the zone adds it.
- **`CF-Connecting-IP` on such a request.** Cloudflare refuses a request in which the visitor sent that header themselves (Error 1000), so on a request that passed through the zone, the value is Cloudflare's.

## Cloudflare setup it assumes

- A Request Header Transform Rule on the zone sets `X-Origin-Secret` to the secret the app holds, on every request to the app's hostnames. Generate the value with `openssl rand -hex 32`.
- The "Remove visitor IP headers" managed transform is off, and no other Transform Rule or Worker removes or rewrites `CF-Connecting-IP`.
- Leave Pseudo IPv4 off: in Cloudflare's "overwrite headers" mode an IPv6 visitor's address is replaced with a made-up IPv4 address from `240.0.0.0/4`, and the gem records that address.

## Secrets

The gem reads two secrets, each from an environment variable first and from the app's credentials second:

| Secret | Environment variable | Credential |
| --- | --- | --- |
| Current, required to switch the gem on | `CLOUDFLARE_ORIGIN_SECRET` | `cloudflare_origin_secret` |
| Previous, being rotated out, optional | `CLOUDFLARE_ORIGIN_SECRET_PREVIOUS` | `cloudflare_origin_secret_previous` |

Each secret is resolved on its own: a non-blank environment variable wins over the credential. A variable left set on the host therefore overrides the credential without any warning, so a stale one keeps an old value in force after you rotate the credential.

Both secrets are accepted, so the value rotates without an outage: set the new value as the current secret and the old one as the previous secret, deploy, switch the Transform Rule to the new value, then remove the previous one.

A secret that is present but shorter than 32 characters fails the boot, so a broken value stops a deploy instead of answering every request with a 403. A blank secret counts as absent.

## When it is on

The middleware is installed only when a current secret is present, and never in the `development` and `test` environments, even when a secret is set, so local requests and specs see the headers they send.

When no current secret is present, the gem installs nothing. Outside `development` and `test` it logs a warning at boot saying the middleware is not installed. An asset build that boots without credentials has no secret, so it is simply off.

## Requirements

Ruby 4.0 or newer and Rails 8.1 or newer. The gem targets the latest Ruby and Rails only, and these floors move up with each release.

## Development

```sh
bundle install
bundle exec rake test
bundle exec standardrb
```

## License

MIT. See [LICENSE](LICENSE).
