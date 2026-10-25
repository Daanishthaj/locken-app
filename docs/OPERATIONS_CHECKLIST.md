# Operations checklist: the 111 "who's gonna tell vibe coders" items

Checked on 2026-10-24 against Locken as it is built today. That means two desktop apps (Mac, SwiftUI; Windows, Tauri), a static website on Vercel, and Supabase, which holds only accounts, profiles, focus totals, feedback and an audit log. Most work happens on the student's own computer.

The list comes from a viral Instagram carousel (nataindata, October 2026). It was written for teams running their own servers at scale. Many items don't apply to an app with no servers of its own, and the table says why rather than adding machinery Locken doesn't need.

**Key:**
- ✅ handled
- ➖ not needed, with the reason
- ⚠️ a gap, with what fixes it

| # | Item | Status | How it's handled in Locken |
|---|---|---|---|
| 1 | Rate limiting | ✅ | Supabase server limits on sign-in, sign-up, codes and resets; client backoff on Mac and Windows (`SECURITY_CHECKLIST.md` #13) |
| 2 | Caching | ✅ | Vercel caches the static site; the apps keep data locally; account requests skip disk caches on purpose (`SecureNetwork`) |
| 3 | Load balancing | ➖ | No servers of our own; Vercel and Supabase balance their own traffic |
| 4 | Reverse proxies | ➖ | Vercel's edge sits in front of the site; nothing to run |
| 5 | API gateways | ➖ | Supabase's gateway (Kong) fronts the database and Edge Functions |
| 6 | CI/CD | ✅ | GitHub Actions: Windows build and tests, security scans (OSV, Semgrep), uptime check; Mac releases are scripted (`scripts/make-release-dmg.sh`, `release-signing.swift`) |
| 7 | Docker | ➖ | Nothing runs in containers; desktop apps and a static site |
| 8 | Kubernetes | ➖ | Same as above |
| 9 | Service discovery | ➖ | Two fixed endpoints (Supabase project URL, site URL) |
| 10 | Circuit breakers | ➖ | Each request is user-initiated; failures show a friendly message instead of piling up retries |
| 11 | Timeouts | ✅ | Every Mac request sets `timeoutInterval`; Windows Rust requests use reqwest timeouts |
| 12 | Retries | ✅ | AI requests retry once on a temporary failure (Mac `retryingOnce`, Windows AI); sign-in retries are throttled by backoff |
| 13 | Exponential backoff | ✅ | Sign-in failures: 1 s doubling to 16 s (Windows), 30 s doubling to 5 min (Mac lockout) |
| 14 | Idempotency | ✅ | Delete Account can be repeated safely; profile saves overwrite the same row; updates check the build number before installing |
| 15 | Message queues | ➖ | No background jobs between servers |
| 16 | Pub/Sub | ➖ | Same |
| 17 | Event-driven architecture | ➖ | Same; inside the apps, EventKit and file watchers already notify changes |
| 18 | Distributed transactions | ➖ | One database; each write touches one row set |
| 19 | Saga pattern | ➖ | Same |
| 20 | Dead letter queues | ➖ | No queues |
| 21 | Cron jobs | ✅ | Audit-log pruning trigger (24 months); GitHub Actions on a schedule (security scans weekly, uptime every 6 h) |
| 22 | WebSockets | ➖ | Not used |
| 23 | Long polling | ➖ | Not used |
| 24 | Server-sent events | ✅ | Only as the AI providers' own streaming; nothing of ours |
| 25 | Database indexing | ✅ | Primary keys and `user_id` indexes; Supabase advisor shows only "unused index" info notices |
| 26 | Query optimization | ✅ | RLS policies wrap `auth.uid()` in `select` (evaluated once per query, per Supabase's advisor) |
| 27 | N+1 queries | ✅ | Each screen makes one request per table |
| 28 | Connection pooling | ✅ | Supabase's pooler (Supavisor) in front of Postgres |
| 29 | Read replicas | ➖ | Traffic is tiny |
| 30 | Sharding | ➖ | Same |
| 31 | Partitioning | ➖ | Same; the audit log prunes itself instead |
| 32 | Replication | ➖ | Managed by Supabase |
| 33 | Leader election | ➖ | No cluster of our own |
| 34 | CAP theorem | ➖ | One database; local data on each computer is the source of truth for focus history |
| 35 | Eventual consistency | ✅ | Birth month/year and consent live on the account so every computer converges on the same answer |
| 36 | Optimistic locking | ➖ | One user edits their own rows; no concurrent editors |
| 37 | Pessimistic locking | ➖ | Same |
| 38 | Distributed locks | ➖ | Same; the Windows app is single-instance (`tauri-plugin-single-instance`) |
| 39 | Race conditions | ✅ | One app instance per computer; sessions saved atomically to one file per account |
| 40 | Deadlocks | ✅ | Kokoro voice engine and CoreML calls are serialized by their own locks; no shared locks in our code |
| 41 | Memory leaks | ✅ | Web views and 3D scenes are torn down when hidden; Assistant model kept loaded on purpose (one copy) |
| 42 | Garbage collection | ➖ | Swift uses ARC; JS and Rust manage their own |
| 43 | Thread safety | ✅ | UI state on `@MainActor`; background work hands results back to the main actor |
| 44 | Backpressure | ✅ | Speech audio is synthesized about 2 s ahead of playback (`paceToRealtime`) |
| 45 | Autoscaling | ➖ | Vercel and Supabase scale themselves; the apps run on the user's computer |
| 46 | Horizontal scaling | ➖ | Same |
| 47 | Vertical scaling | ➖ | Same; Supabase plan size is the only knob |
| 48 | CDN | ✅ | Vercel's CDN serves the site, the DMG and the Windows installer |
| 49 | Edge caching | ✅ | Same |
| 50 | Cache invalidation | ✅ | Each Vercel deploy is immutable; aliasing swaps everything at once; hashed asset names |
| 51 | Feature flags | ✅ | `maintenanceMode` in `version.json`; per-user switches in Settings (AI, Commitment mode, Assistant calendar access) |
| 52 | Blue-green deployment | ✅ | Every site deploy gets its own URL and is checked before `vercel alias set` moves the live name to it |
| 53 | Canary releases | ⚠️ | Not done: every installed app takes a new build at once. Acceptable at this size; if users grow, add a `rolloutPercent` to `version.json` |
| 54 | Rolling deployments | ➖ | Desktop apps update one computer at a time on their own |
| 55 | Rollbacks | ✅ | Site: `vercel alias set` back to the previous deployment. Apps: publish the previous signed DMG with a higher build number. Database: migrations are additive |
| 56 | Health checks | ✅ | `.github/workflows/uptime.yml` (new): site, both downloads, a well-formed `version.json`, Supabase auth |
| 57 | Liveness and readiness probes | ➖ | No long-running services of our own |
| 58 | Monitoring | ✅ | Uptime workflow every 6 h; Supabase dashboard and advisors; Vercel deployment logs |
| 59 | Logging | ✅ | Supabase auth and API logs; the Mac updater writes its own log (`~/Library/Logs/Locken/updater.log`); no personal data in logs |
| 60 | Distributed tracing | ➖ | No chain of services to trace |
| 61 | Metrics | ✅ | Owner-only admin console: sign-ins, builds, retention, from Supabase auth records (disclosed in the Privacy Policy) |
| 62 | Alerts | ✅ | A failed uptime or security run emails the repo owner (GitHub notifications) |
| 63 | SLOs | ➖ | Free app, no promise of uptime; the Terms say the service is provided as is |
| 64 | SLIs | ➖ | Same |
| 65 | Error budgets | ➖ | Same |
| 66 | Observability | ✅ | Items 56–62 together |
| 67 | Secrets management | ✅ | Keychain (Mac), Credential Manager (Windows), Supabase secrets (server); pre-commit secret scan; full history scanned |
| 68 | IAM | ✅ | RLS on every table; admin access checked server-side against the `admins` table; service-role key only in Edge Functions |
| 69 | OAuth | ✅ | Google sign-in through Supabase with PKCE; the `locken://` return link is exchanged once |
| 70 | JWT rotation | ✅ | Supabase short-lived access tokens with refresh-token rotation; Sign Out Everywhere revokes all sessions |
| 71 | TLS | ✅ | HTTPS only; HSTS with preload on the site; no App Transport Security exceptions on Mac |
| 72 | Encryption at rest | ✅ | Supabase encrypts storage; local data relies on FileVault / BitLocker (documented in the Privacy Policy) |
| 73 | Encryption in transit | ✅ | Same as TLS |
| 74 | WAF | ✅ | Vercel's firewall in front of the site; nothing writable on it |
| 75 | DDoS protection | ✅ | Vercel and Supabase platform protection; the site is static |
| 76 | CORS | ✅ | The site makes no cross-origin requests (CSP `connect-src 'self'`); Supabase checks keys and tokens, not origins |
| 77 | CSRF | ✅ | No cookies are used for auth; tokens are sent explicitly |
| 78 | SQL injection | ✅ | Supabase REST only, no string-built SQL |
| 79 | XSS | ✅ | Strict CSP on the site; user text rendered as text in all apps; Markdown parsed into DOM nodes, never HTML |
| 80 | SSRF | ✅ | No server fetches user-supplied URLs; Canvas requests are locked to the host the student typed, from their own computer |
| 81 | Database migrations | ✅ | `supabase/migrations/`, applied in order, kept in git |
| 82 | Schema versioning | ✅ | Dated migration files are the version history |
| 83 | Disaster recovery | ✅ | The runbook below; the apps keep working offline with local data if Supabase is down |
| 84 | Backups | ⚠️ | Supabase's daily backups need the Pro plan. Until then, the lost data would be limited to accounts and profiles, since focus history lives on each computer. Fix: Pro plan ($25/month), or a weekly `supabase db dump` that you run (it needs the database password) |
| 85 | Failover | ➖ | Managed by Vercel and Supabase |
| 86 | Multi-region deployment | ➖ | The site is global through the CDN; one Supabase region is enough |
| 87 | Chaos engineering | ➖ | Not worth it at this size; offline behaviour is tested by hand |
| 88 | Cost optimization | ✅ | Free tiers; static site; AI and voice run on the user's own key or computer, so cost doesn't grow with users |
| 89 | Cold starts | ✅ | Edge Functions are only used for Delete Account and the admin console; a short delay is fine there |
| 90 | Serverless limits | ✅ | Edge Functions do one small job each, well under limits |
| 91 | Latency | ✅ | Static files from the CDN; local-first apps |
| 92 | Throughput | ➖ | Traffic is tiny |
| 93 | P99 latency | ➖ | Same |
| 94 | Tail latency | ➖ | Same |
| 95 | Network partitions | ✅ | The apps work offline; account sync waits until the network is back |
| 96 | Clock skew | ✅ | Tokens are checked by Supabase's clock, not the computer's; session timers only measure time on one computer |
| 97 | DNS | ✅ | Vercel-managed domain |
| 98 | TCP vs UDP | ➖ | Everything is HTTPS |
| 99 | HTTP/2 and HTTP/3 | ✅ | Served by Vercel and Supabase automatically |
| 100 | gRPC | ➖ | Not used |
| 101 | Webhooks | ➖ | None received or sent |
| 102 | API versioning | ✅ | `version.json` carries a build number; old apps ignore fields they don't know |
| 103 | Semantic versioning | ✅ | Version name plus build number (`locken-version-naming`): small updates bump the build, batches bump the version |
| 104 | Infrastructure as code | ✅ | Migrations, `vercel.json`, GitHub workflows and Tauri capabilities are all in git |
| 105 | Terraform | ➖ | Nothing to provision beyond the above |
| 106 | Helm charts | ➖ | No Kubernetes |
| 107 | Build caching | ➖ | Windows CI builds from scratch (about 10 minutes); add `actions/cache` for Cargo if it gets slow |
| 108 | Dependency hell | ✅ | Lockfiles committed, exact pins for the Swift package, OSV-Scanner on every lockfile |
| 109 | Production incidents | ✅ | The runbook below |
| 110 | On-call | ✅ | The owner gets the uptime and security emails |
| 111 | Postmortems | ✅ | Write one in `docs/incidents/` after anything users noticed; for example, the 2026-10-19 site outage from a `--prebuilt` deploy is recorded in the deploy notes |

## Incident runbook

1. **Site down or a bad deploy:** run `vercel alias set <previous deployment> locken-app.vercel.app`. The previous deployment is listed in Vercel. Then check that `/` returns 200 and `version.json` shows the right build.
2. **A bad app release:** sign and publish the previous good DMG with a higher build number (`scripts/release-signing.swift`), or set `maintenanceMode: true` in `version.json` to stop new installs while you fix it.
3. **Supabase down:** the apps keep working with local data, and nothing needs doing. Sign-in and the admin console come back on their own.
4. **A leaked key:**
   - publishable key: rotate it in Supabase and ship a build with the new one
   - release signing key: generate a new one, ship a build that trusts it, and retire the old one
5. **Afterwards:** write a short postmortem covering what happened, how it was noticed, the fix, and what stops it happening again.

## What's left

- **Backups (#84):** needs your decision, either the Supabase Pro plan or a weekly dump you run yourself.
- **Canary releases (#53):** fine to skip until there are many users.
