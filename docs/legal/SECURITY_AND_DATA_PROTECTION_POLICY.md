# Locken Security & Data Protection Policy

**Effective date:** October 16, 2026
**Last reviewed:** October 16, 2026
**Policy owner:** Locken Security Coordinator (daanu.focus@gmail.com)

## 1. Purpose and scope

This Policy describes how Locken ("**we**", "**us**") protects personal information and the Locken Service, how we respond to security incidents and data breaches, and how security researchers can report vulnerabilities. It is our written information security program. It applies to:
- the Locken macOS applications (including test and preview builds), the Locken website and its update channel;
- our account infrastructure and every service provider that processes personal information for us;
- everyone who has access to our systems or personal information, including founders, employees, contractors and volunteers ("**Personnel**").

## 2. Roles and responsibilities

| Role | Responsibility |
|---|---|
| **Security Coordinator** (daanu.focus@gmail.com) | Owns this Policy and the security program; approves access to production systems; leads incident response; makes notification decisions with legal counsel; runs the annual review. |
| **Personnel** | Follow this Policy; protect credentials and devices; report suspected incidents to the Security Coordinator immediately. |
| **Service providers** | Protect our data under written agreements; notify us of incidents affecting our data without undue delay. |
| **Legal counsel** (none retained at present) | Advises on breach-notification duties and regulator communications. |

## 3. Security principles

1. **Data minimization and local-first design.** We collect only what an account needs. Focus history, screen usage, notes, Canvas data and AI keys stay on the user's Mac.
2. **Least privilege.** Each person, system and key gets only the access it needs.
3. **Server-side enforcement.** Identity comes from verified tokens; access rules are enforced on the server, never only in the app's interface.
4. **Defense in depth.** Multiple independent controls protect each asset.
5. **Secure by default.** Optional data flows are off until the user turns them on.
6. **Honesty.** We describe our security accurately, including our limitations (Section 12).

## 4. Data classification

| Class | Examples | Handling |
|---|---|---|
| **Restricted** | Password hashes, session and refresh tokens, two-step verification secrets, the database service-role key, the release-signing private key, email-delivery credentials; users' Canvas tokens and AI keys (on their Macs only) | Never in source code, logs, the website or app bundles. Stored only in a secrets store (macOS Keychain or the provider's encrypted secret storage). Access limited to the Security Coordinator. |
| **Confidential** | Account email, name, profile image; security logs containing IP addresses; support and privacy-request emails; users' local private data (on their Macs only) | Accessible only to authorized Personnel for a stated purpose. Encrypted in transit and at rest. |
| **Internal** | Source code, configuration without secrets, internal documentation | Access limited to Personnel; protected by the repository host's access controls. |
| **Public** | Website content, the public (anon) database key, the release-signing public key | May be published. The anon key is public by design; server-side access rules make that safe. |

## 5. Technical safeguards

### 5.1 Encryption
- All network traffic between the apps, our servers and third parties uses TLS (HTTPS). macOS App Transport Security is left at its secure default.
- Our database provider encrypts data at rest.
- Tokens and keys on users' Macs are stored in the macOS Keychain, device-only where supported. Users' local files rely on macOS account protection and FileVault (Section 12).

### 5.2 Authentication and account security
- Passwords: at least 8 characters, following NIST SP 800-63B; common, repetitive, sequential and known-breached passwords are rejected (breach check by k-anonymity, so the password never leaves the Mac). Passwords are stored only as salted hashes by our authentication provider.
- Every new sign-in requires a 6-digit code sent by email that expires after 10 minutes.
- Optional authenticator-app (TOTP) two-step verification; accounts that enroll must pass it, and it is enforced by server-side policies.
- One generic error for a wrong email or password; sign-up and reset never reveal whether an account exists.
- Rate limiting on the server for sign-in, sign-up, codes and resets, plus progressive client-side lockouts after repeated failures.
- Sign-out revokes the session on the server, not just on the device. Users can also sign out on every device at once.
- Changing a password needs a code sent to the account's email, and signs out the account's other devices.
- Optional Google sign-in uses OAuth with PKCE.

### 5.3 Access control and data isolation
- Row Level Security is enabled on every database table, with owner-only policies tied to the verified user ID. The public key has no privileges on account tables.
- Functions that run with elevated privileges are not callable by public or ordinary users.
- On shared Macs, each account's local files, settings and Keychain items are kept separate.

### 5.4 Secrets management
- Only the public database key ships in the apps or the website.
- The service-role key exists only in the account-deletion server function's encrypted environment.
- The release-signing private key is held only in the publisher's Keychain.
- A pre-commit hook blocks API keys, private keys, service-role tokens and `.env` files from entering the code repository; the full repository history has been scanned for leaked secrets.

### 5.5 Application security
- The distraction blocker closes only games, social-media and video apps and matching browser tabs; work apps are protected and unknown apps keep running. Locken never requests Full Disk Access.
- Embedded web views can load only the app's own bundled pages and accept only a fixed set of messages.
- Input that reaches system scripts is reduced to safe characters (unit-tested); HTML from third parties is never rendered as code.
- Canvas tokens are sent only over HTTPS to the exact host the user entered; pagination cannot redirect them elsewhere.
- No debug logging of tokens or personal data in release builds; web views are not inspectable in release builds.
- Users see friendly error messages; technical details stay out of the interface.

### 5.6 Software update integrity
- Every in-app update must carry a valid Ed25519 signature, made with our release key, over the version, build number and file checksum, and must match its published SHA-256 checksum before it is installed.
- The updater never removes macOS quarantine protections.

### 5.7 Website security
- Security headers: Content Security Policy, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy and Cross-Origin-Opener-Policy. Third-party scripts are pinned with Subresource Integrity where supported.
- No cookies, analytics or advertising scripts.

### 5.8 Secure development
- Every change to sign-in, data handling, the database, the updater, or anything that controls other apps is checked against our security checklist before release.
- Dependencies are audited for known vulnerabilities before release.
- Database changes are made through reviewed migrations and checked with our provider's security advisors.
- After each security-relevant change we test as an untrusted user (public key, forged tokens, other users' IDs) and confirm access is refused.

## 6. Administrative safeguards

- **Access to production systems** (database provider, hosting, code repository, domain and email accounts) is limited to named Personnel approved by the Security Coordinator, and is reviewed [quarterly]. **[owner to confirm]**
- **Multi-factor authentication** is required on every account with access to production systems, the code repository, the release-signing key or user data. **[owner to confirm]**
- **Offboarding:** access is removed and shared secrets are rotated within [24 hours] when someone leaves or no longer needs access. **[owner to confirm]**
- **Training:** Personnel read this Policy and the security docs before receiving access, and again after each annual review.
- **Risk assessment:** the Security Coordinator reviews risks to personal information at least annually and after any significant change, updating `docs/THREAT_MODEL.md`.
- **Vendor management:** we choose service providers that (a) sign a data-processing agreement limiting use of our data to providing services to us, (b) commit to notify us of incidents without undue delay, (c) provide appropriate transfer safeguards, and (d) maintain recognized security practices [such as SOC 2 reports — verify per provider]. We review each provider when engaged and annually. **[owner to confirm DPAs are signed]**

## 7. Physical and device safeguards

- Our servers are hosted by cloud providers responsible for the physical security of their data centers.
- Devices used to access production systems or hold the release-signing key must use full-disk encryption (FileVault), a screen lock, current operating-system updates and a strong account password. **[owner to confirm]**
- Lost or stolen devices must be reported to the Security Coordinator immediately so that sessions and keys can be revoked (Section 9.6).

## 8. Data retention and disposal

- We keep personal information only for the periods listed in Section 8 of our [Privacy Policy](PRIVACY_POLICY.md).
- **Account deletion:** when a user deletes their account, the server account and all linked database rows are deleted immediately; backups expire on the provider's schedule. The app also erases that account's local data on the Mac.
- **Children under 13:** information is deleted promptly once discovered.
- Disposal uses the provider's deletion functions or secure erasure. Paper records are not kept.

## 9. Incident response and breach notification

### 9.1 Definitions
- **Security incident:** any event that actually or potentially compromises the confidentiality, integrity or availability of the Service or personal information.
- **Personal data breach:** a security incident that leads to the accidental or unlawful destruction, loss, alteration, unauthorized disclosure of, or access to, personal information.

### 9.2 Severity levels

| Level | Examples | Response |
|---|---|---|
| **SEV-1 Critical** | Confirmed unauthorized access to account data; leak of the service-role key, release-signing key or email credentials; a malicious update served to users | Immediate. Security Coordinator leads; all other work stops. |
| **SEV-2 High** | Exploitable vulnerability with no evidence of use; compromise of a provider that may affect our data | Same day. |
| **SEV-3 Moderate/Low** | Limited misconfiguration with no personal data exposure; blocked attack attempts | Within [5] business days. |

### 9.3 Response phases
1. **Report and log.** Anyone who suspects an incident reports it to the Security Coordinator at once (daanu.focus@gmail.com, [phone]). The Coordinator opens an incident record with the time of discovery.
2. **Triage (within 24 hours of discovery).** Confirm whether an incident occurred, assign a severity, and determine what data, systems and users may be affected.
3. **Contain.** Stop the exposure: revoke sessions, rotate keys, disable affected features, pull compromised files from the website.
4. **Investigate.** Preserve logs and evidence; determine cause, scope, timeline and the people and data affected.
5. **Notify.** Decide notification duties with legal counsel using Section 9.4.
6. **Recover.** Fix the root cause, restore normal operation, verify the fix, and monitor for recurrence.
7. **Review (within [14] days of closure).** Write a post-incident review covering what happened, why, what worked and what will change; update this Policy, the threat model and the checklist.

### 9.4 Notification timelines

| Who | When |
|---|---|
| **EEA/UK supervisory authority** | Without undue delay and **within 72 hours** of becoming aware of a personal data breach, unless it is unlikely to result in a risk to individuals. If information is incomplete, we notify in phases. |
| **Affected individuals** | **Without undue delay**, and in any event **no later than 30 days** after confirming the breach (or sooner where a law requires), when the breach is likely to result in a high risk to them (EEA/UK) or when US state law requires notice. Delay is permitted only if law enforcement requests it in writing. |
| **US state attorneys general and other regulators** | As required by each state's law, typically where a set number of residents (often 500 or 1,000) are affected. |
| **Schools or districts** (if we ever hold their data under contract) | As required by the agreement, and no later than 72 hours. |
| **Service providers to us** | Our agreements require them to notify us without undue delay [and within 48 hours]. |

### 9.5 What notices contain
- what happened and when, as far as known;
- the categories and approximate number of people and records affected;
- the likely consequences;
- what we have done and will do to address the breach and reduce harm;
- what affected people can do to protect themselves (for example, change passwords, enable an authenticator app, watch for phishing); and
- how to contact us for more information.

Notices to individuals go by email to the account address and, where appropriate, in the app and on the website. We keep a record of every personal data breach, including those not notified, with the facts, effects and remedial action.

### 9.6 Playbooks for Locken's highest-risk scenarios

| Scenario | Immediate actions |
|---|---|
| Session tokens or the database signing secret exposed | Revoke all sessions and refresh tokens; rotate the JWT signing key; force re-authentication; review authentication logs. |
| Service-role key exposed | Rotate the key immediately; update the server function's secret; review database and function logs for misuse. |
| Public key abused (scraping or spam) | Confirm access rules held; tighten rate limits; enable CAPTCHA; rotate the public key in a new app release if needed. |
| Release-signing private key exposed | Remove the update feed from the website so no update is offered; publish a security notice; generate a new key; ship a new build for manual download with its checksum published through a separate channel; tell users to reinstall from the official site. |
| Website or hosting account compromised | Take down altered files; rotate hosting tokens; verify the published installer against the signed release; publish a notice. (In-app updates reject unsigned files.) |
| Email-delivery account compromised | Rotate credentials; revoke sessions; warn users about phishing; move delivery to a dedicated provider. |
| Provider breach (database, hosting, email) | Obtain details from the provider; assess our exposure; follow Section 9.4. |
| Maintainer device lost or stolen | Revoke its sessions and tokens; rotate any key it held; check logs for misuse. |

## 10. Vulnerability disclosure

We welcome reports from security researchers.

- **How to report:** email daanu.focus@gmail.com with a description, steps to reproduce, the impact, and any proof of concept. Please do not open a public issue.
- **Our response:** we acknowledge reports **within 7 days**, keep you informed of progress, and prioritize fixes for anything that could expose account data ahead of other work. We will credit you publicly if you wish. We do not currently offer monetary rewards.
- **Scope:** the Locken apps, the Locken website and the Locken account service as reached through the apps' normal interfaces.
- **Out of scope:** denial-of-service testing, spam, social engineering, physical attacks, attacks on other users or their devices, and testing of third-party services (Canvas, AI providers, Google, Apple), which have their own programs.
- **Rules:** use only accounts you created; access the minimum data needed to demonstrate an issue, and never keep, share or alter other people's data; stop and report immediately if you encounter personal data; give us reasonable time to fix the issue before disclosure (we suggest 90 days).
- **Safe harbor:** if you act in good faith and follow these rules, we will not pursue or support legal action against you for your research, and we consider it authorized under applicable anti-hacking and anti-circumvention laws to the extent we are able to authorize it. If a third party brings legal action against you for activities that complied with this Policy, we will make that clear.

## 11. Your role as a user

- Download Locken only from https://locken-app.vercel.app or update it from inside the app.
- Keep macOS up to date and turn on FileVault, which protects the data Locken stores on your Mac.
- Use a unique password and turn on an authenticator app.
- Never share sign-in codes. We will never ask for your password or codes.
- Protect your Canvas token and AI keys; revoke them with the provider if you think they were exposed.
- Report suspicious activity to daanu.focus@gmail.com.

## 12. Known limitations

We believe in telling you where our protections stop:
- **Apple notarization:** Locken is not yet signed with an Apple Developer ID or notarized, so macOS cannot vouch for it. In-app updates are protected by our own signature (Section 5.6), and we plan to add notarization [target date].
- **Server-side leaked-password protection** is not enabled with our authentication provider. The apps check new passwords against known breaches themselves, but this check runs on the device.
- **Local files are not separately encrypted by Locken.** They rely on your macOS account and FileVault.
- **Third-party services** you connect (Canvas, AI providers, Google) are outside our control.
- **Some optional features contact third parties directly** (Section 3 of our Privacy Policy), which reveals your IP address to them.

## 13. Review and changes

The Security Coordinator reviews this Policy at least once a year, after any SEV-1 incident, and whenever the Service changes how it handles personal information. Material changes to commitments in this Policy that affect users will be announced as described in our Terms of Service.

## 14. Contact

Security reports: daanu.focus@gmail.com
Privacy questions: daanu.focus@gmail.com
Locken

---

*This document was prepared as a template and does not constitute formal legal advice. Consult a qualified attorney before relying on it.*
