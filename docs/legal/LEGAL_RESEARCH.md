# Locken legal research and strategy (Phase 1)

> **Not legal advice.** This research and the documents built from it were generated to help organize the work. They are not formal legal counsel and do not create a lawyer–client relationship. Laws change and their application depends on facts. Have a licensed attorney in your jurisdiction review everything before you publish or rely on it.

Prepared 2026-10-11. Every product fact below was checked against Locken's code and its security docs (`docs/AUTH.md`, `docs/DATA_SECURITY.md`, `docs/THREAT_MODEL.md`) on that date. The legal documents in this folder must stay true to the product. A privacy policy that promises more than the app does is itself a violation (FTC Act §5).

## 0. What Locken is (the facts the documents rely on)

| Area | Fact |
|---|---|
| Product | Free macOS focus app for students: focus sessions, a distraction blocker, check-ins, notes, habits, Canvas LMS assignments, optional AI goal-writing. Two builds: main Locken app and Locken Test App. Marketing website on Vercel. |
| Audience | Students. Sign-up asks the user to confirm they are 13 or older. Nothing stops high-school or college students; some will be minors (13–17). |
| Accounts | Supabase Auth (project in **us-east-2, Ohio, USA**). Server holds email, hashed password, name, avatar URL, optional authenticator (TOTP) factor. Optional Google sign-in (OAuth with PKCE). Main app also has a fully local guest mode. |
| Data on the Mac only | Focus stats, screen usage (front app name and category, browser **domain only**, 35-day rolling), notes, habits, milestones, listening time per song, AI plans, Canvas link and token, AI keys, session tokens (Keychain). Per-account separation on shared Macs. |
| Data that leaves the Mac | Email and 6-digit codes via Gmail SMTP; first 5 characters of a SHA-1 password hash to Have I Been Pwned; the user's Canvas token to their own school's Canvas host; goal text, session length and assignment titles to the AI provider the user picks, with the user's own key (Claude, Gemini; main app also OpenAI, DeepSeek, xAI); update checks and downloads from Vercel; radio from zeno.fm; one hero image from Unsplash. |
| Not present | No analytics, ads, crash reporters, tracking pixels, cookies or browser storage on the website, file uploads, storage buckets, payments, public user content, or messaging between users. |
| Device control | The blocker quits games, social-media and YouTube apps (`NSRunningApplication.terminate`) and closes matching browser tabs in Safari, Chrome and Arc through Apple Events. It can turn on macOS Focus/Do Not Disturb. It never needs Full Disk Access. |
| Distribution | DMG from the website. Not signed with an Apple Developer ID or notarized. In-app updates verified by an Ed25519 signature and SHA-256. |
| Deletion | Settings → Delete Account removes the server account (profile and sessions cascade) and erases that account's local data. |

## 1. Regulatory frameworks that apply

| Framework | Applies to Locken? | Why | What it demands from us |
|---|---|---|---|
| **FTC Act §5** (US, unfair or deceptive practices) | **Yes** | Any business making privacy or security promises to US consumers. | Policies must match real practice. "Reasonable" security. FTC orders against edtech (Chegg 2023, Edmodo 2023) set the bar: written security program, MFA, encryption, a documented retention schedule, easy access and deletion requests. |
| **COPPA** + **amended COPPA Rule** (US, under-13s) | **Yes, as a risk to manage** | A student app will attract under-13s (middle school). Amended Rule effective 2025-06-23; compliance required from **2026-04-22**. | Either (a) stay a general/teen service that does not knowingly collect from under-13s, with a *neutral* age screen and deletion when we learn a user is under 13; or (b) obtain verifiable parental consent. The amended Rule adds a written information security program and a published retention policy for children's data. Schools can consent for parents only for strictly educational use (Edmodo). |
| **SOPIPA** (California) and similar state student-privacy laws (about 40 states have one) | **Likely**, if Locken is marketed for K-12 school purposes | Covers operators whose service is designed and marketed primarily for K-12 school purposes, even without a school contract. Canvas integration and student marketing point that way. | No targeted ads using student data, no sale, no profiles for non-educational purposes, reasonable security, delete on school or district request. Locken already does none of the prohibited things; the Privacy Policy now commits to it in writing. |
| **FERPA** (US) | **Not directly** | Locken is direct-to-student: the school does not disclose education records to us. The student links their own Canvas account. | Becomes relevant if a school or district adopts Locken. Then we need a school-official agreement and a district data privacy agreement before receiving roster or record data. |
| **CalOPPA** (California) | **Yes** (no size threshold) | Any online service collecting personal information from California residents. | Conspicuously posted privacy policy: categories collected, third parties, how users review or change data, how changes are announced, effective date, and how we respond to Do Not Track signals and whether third parties track. |
| **CCPA/CPRA** (California) | **Probably not yet** | Applies at $26.625M revenue (2026 figure), 100,000+ consumers bought/sold/shared, or 50%+ revenue from selling data. Locken is free and sells nothing. | Drafted to comply anyway so the policy survives growth: categories table, no sale/no share statement, rights, non-discrimination, authorized agents. Account log-in plus password counts as "sensitive personal information"; we use it only for permitted purposes, so no "limit" link is needed. Breaches of email-plus-password data carry a private right of action (Civ. Code §1798.150): another reason for strong security. |
| **Other US state privacy laws** (about 20 states, including Indiana, Kentucky and Rhode Island from 2026-01-01) | **Mostly not yet** (thresholds, usually 100,000 consumers) | Several states (for example Connecticut and Colorado) added heightened duties for minors' data. | Rights handling, appeal process, no targeted ads or sale of minors' data. Covered by the same commitments. |
| **State data-breach notification laws** (all 50 states, DC, territories) | **Yes** | Email plus password, or account credentials, is a triggering data element in many states. | Notify affected residents in the "most expedient time", with hard deadlines in some states (30 days in several, for example Colorado, Florida and Washington). Regulator notice above set thresholds. |
| **GDPR / UK GDPR** | **Yes, if offered to EU/UK users** (website and DMG are worldwide) | Personal data of people in the EU/UK. | Lawful basis per purpose; Article 13 notice; rights (access, correction, deletion, restriction, portability, objection); processor contracts (Art. 28); transfer safeguards (servers are in the US); breach notice to the regulator within **72 hours** (Art. 33) and to users without undue delay if high risk (Art. 34); records of all breaches. Children's consent age varies **13–16** by country (Art. 8). |
| **UK Age Appropriate Design Code** | **Yes, if UK children are likely users** | Applies to services likely to be accessed by under-18s in the UK. | High-privacy defaults, data minimisation, no nudges, no profiling or sharing by default, a DPIA, child-friendly explanations. Locken's local-first design already fits most of this. |
| **EU AI Act, Article 50** (in application from 2026-08-02) | **Light touch** | Locken *uses* AI models through the user's key; it is not a model provider. The rephrase feature is not a chatbot or deepfake tool. | Label AI-generated suggestions as AI-generated and keep the user in control of edits. No marking duty falls on Locken as a deployer of text suggestions the user reviews. |
| **Platform and vendor terms** | **Yes** | Contracts, not statutes, but breaking them can cost us access. | See section 2.4. |
| **Consumer-protection and contract law** | **Yes** | Minors can usually void (disaffirm) contracts; EU/UK and Australian law void unfair terms and mandatory-right waivers. | Clickwrap acceptance; parent or guardian agreement for minors; liability limits that carve out what the law won't let us exclude; no mandatory arbitration by default (section 3). |

## 2. Liabilities and standards specific to this kind of app

### 2.1 An app that controls other apps
Locken quits apps and closes browser tabs. A user could lose unsaved work and blame us. Standard protection:
- **Design:** work apps are protected first; unknown apps keep running; only games, social media and YouTube are closed. This is already true and must stay true.
- **Terms:** clear notice that Locken may quit apps and close tabs, a duty on the user to save work and set the blocker up, and a disclaimer of liability for lost unsaved work.

### 2.2 Screen-usage tracking (stalkerware risk)
Locken records which app is in front and which domains are open. Installed on someone else's Mac without their knowledge, that is covert monitoring, which is unlawful in many places. Standard protection:
- **Acceptable Use:** install only on Macs you own or are authorized to use; never use Locken to monitor another person without their knowledge and consent.
- **Privacy:** state plainly that this data never leaves the Mac.

### 2.3 Students and minors
- **COPPA age screen.** A checkbox that says "I'm 13 or older" is *not* a neutral age screen under FTC guidance, because it tells the child the answer that works. Recommended: ask for a birth month and year with no hint of the cutoff, block under-13s, and remember the block so the child can't simply retry.
- **Marketing.** Market to students 13 and up (high school and college). Advertising to elementary or middle schools can make Locken "directed to children", and then an age screen is no longer enough.
- **Minors' contracts.** Users 13–17 can usually disaffirm contracts. Courts have refused to compel arbitration against minors (the EA *Apex Legends* case, California Court of Appeal) and occasionally enforced it (*Garcia v. Roblox*, C.D. Cal. 2026). Ask for a parent or guardian's agreement, and don't build the whole dispute strategy on arbitration.

### 2.4 Third-party credentials and AI providers
- **Canvas tokens and AI keys** are the user's own credentials. They stay in the Keychain and go only to their own service. The Terms must say the user is responsible for complying with that service's terms and their school's policies.
- ⚠️ **Age conflict with AI provider terms.** Google's Gemini API Additional Terms require users to be **18+** and forbid using the API in apps "directed towards or likely to be accessed by" under-18s. Anthropic's terms also set 18 as the minimum age (verify the current commercial terms). Locken admits 13–17-year-olds. Options: (a) show AI features only to users who confirm they are 18+, (b) drop Gemini, or (c) accept the risk and tell users that they must meet each provider's age rules. **Recommended: (a).** The Terms below already require users to meet provider age rules.
- **Google user data.** Google sign-in uses basic scopes. Any Google Calendar access uses sensitive scopes and needs Google's OAuth verification, a privacy policy on a verified domain, and the **Limited Use** commitment. The Privacy Policy includes that statement.
- **AI output.** AI suggestions can be wrong. The Terms disclaim accuracy, keep the user responsible, and point to their school's academic-integrity rules.

### 2.5 Software distribution
- The app isn't notarized, so users bypass Gatekeeper with right-click → Open. The Terms and Security Policy tell users to download only from the official site and explain how updates are verified. Notarization reduces both malware-impersonation risk and liability.

### 2.6 Security standard of care
"Reasonable security" in FTC orders and state laws now means: a written security program with a named owner, MFA, encryption in transit and at rest, least-privilege access, a written retention schedule, vendor oversight, an incident-response plan, and easy access and deletion requests. Locken already meets most of these technically (`docs/SECURITY_CHECKLIST.md`). The Security & Data Protection Policy writes them down and adds the breach protocol.

### 2.7 Breach-notification timelines

| Audience | Deadline |
|---|---|
| EU/UK regulator | Within 72 hours of becoming aware, unless unlikely to risk people's rights |
| EU/UK individuals | Without undue delay if high risk |
| US individuals | Most expedient time; hard deadlines of 30–60 days in many states (30 in several) |
| US regulators (state attorneys general) | Varies; often when 500 or 1,000+ residents are affected |
| Schools or districts (if ever under contract) | As the data privacy agreement says, often 72 hours |

The Security Policy sets one internal rule that meets the strictest: assess within 24 hours, regulators within 72 hours, users without undue delay and **no later than 30 days**.

## 3. Strategy decisions built into the drafts

1. **Truthful, specific, local-first.** The policies describe exactly what Locken does today. Where the honest answer is a gap (no notarization, no server-side leaked-password check), the Security Policy says so. This is the strongest FTC defense.
2. **No sale, no ads, no profiling, no AI training.** Stated as binding commitments (SOPIPA-style), because Locken already works that way and it removes most CCPA, state-law and Children's Code exposure.
3. **13+ with parental agreement under 18.** Under-13 accounts are deleted when discovered.
4. **Disputes:** informal resolution first, then small-claims or the courts of the chosen jurisdiction, with EU/UK consumers keeping their home-court rights. Mandatory arbitration is offered only as an optional, bracketed module, because enforcement against minors is unreliable and a free student app gains little from it.
5. **Liability cap:** the greater of what the user paid in 12 months or US$50, with carve-outs the law requires (gross negligence, willful misconduct, death or personal injury, mandatory consumer rights).
6. **Device-control and monitoring clauses** in both the Terms and the Acceptable Use Policy.

## 4. Clauses we must include (and where they are)

| Clause | Why | Document |
|---|---|---|
| Clickwrap acceptance, parent or guardian agreement for minors | *Berman v. Freedom Financial* (9th Cir. 2022); minors' capacity | Terms §1–2 |
| Eligibility 13+, under-13 deletion | COPPA | Terms §2, Privacy §10 |
| Automated actions on your Mac (quits apps, closes tabs, Focus mode) and save-your-work duty | Device-control liability | Terms §5 |
| Third-party services and provider age rules | Vendor terms (Gemini, Anthropic, Canvas, Google) | Terms §6 |
| AI output disclaimer and academic integrity | Accuracy, misuse | Terms §7, AUP §3.5 |
| Limited software license and reverse-engineering limits (where law allows) | IP protection | Terms §10 |
| Signed updates notice | Update integrity | Terms §11, Security §5.6 |
| Disclaimers, liability cap, consumer carve-outs | Standard protection; EU/UK/AU mandatory law | Terms §16–17 |
| Informal dispute resolution, governing law, venue, optional arbitration | Dispute strategy | Terms §19 |
| Termination by user (Delete Account) and by us | Account lifecycle | Terms §15 |
| Data inventory: on-Mac vs server vs direct-to-third-party | GDPR Art. 13, CalOPPA, FTC accuracy | Privacy §1–3 |
| Lawful bases | GDPR Art. 6 | Privacy §4 |
| No sale, no sharing, no targeted ads, no AI training | CCPA/CPRA, SOPIPA, Children's Code | Privacy §5 |
| Google API Limited Use statement | Google User Data Policy | Privacy §7 |
| Retention schedule | Amended COPPA Rule, FTC orders | Privacy §8, Security §8 |
| Rights, verification, agents, appeals, complaints | GDPR, CCPA, state laws | Privacy §9 |
| Children and student-data commitments | COPPA, SOPIPA, FERPA | Privacy §10 |
| International transfers (US servers; DeepSeek in China if chosen) | GDPR Ch. V | Privacy §12 |
| Do Not Track and Global Privacy Control response | CalOPPA, CPRA | Privacy §13 |
| Prohibited conduct, others' devices, covert monitoring | Stalkerware, security | AUP §3 |
| Enforcement ladder and appeals | Fair process | AUP §5–6 |
| Written security program, named coordinator | Amended COPPA Rule, FTC | Security §2 |
| Incident response and breach notification timelines | GDPR Art. 33/34, state laws | Security §9 |
| Vulnerability disclosure with safe harbor | Good practice | Security §10 |

## 5. Gaps to close before publishing these documents

These are product or business actions. The documents assume they will be done; until then, the bracketed text flags them.

1. **Add clickwrap acceptance at sign-up** in both apps: an unchecked box "I agree to the Terms of Service and Privacy Policy" with working links, next to the sign-up button. Without it, the Terms won't bind users (*Berman*). **Done in the Test App on 2026-10-11** (links open the documents in the app; sign-in shows "By signing in, you agree…"); main app pending.
2. **Replace the age checkbox with a neutral birth-month-and-year screen**, block under-13s, and remember the block. **Done in the Test App on 2026-10-11** (plus a parent-or-guardian box for ages 13–17); main app pending.
3. **Resolve the AI provider age conflict** (section 2.4); recommended: AI features only for users who confirm they are 18+. **Done in the Test App on 2026-10-11:** AI features use the birth month and year (asked in Settings if the account has none on this Mac) and are off under 18; main app pending.
4. **Move transactional email off personal Gmail SMTP** (already an open item: Resend). A personal Gmail account offers no processor agreement (GDPR Art. 28), and its Sent folder keeps every code email and address indefinitely. Until then, empty that Sent folder on a schedule.
5. **Name the operator.** The policies need a legal name and contact address (CalOPPA, GDPR Art. 13). If the operator is a minor, a parent, guardian or a company should hold that role; a lawyer should advise.
6. **Set up the contact addresses:** done on 2026-10-13: daanu.focus@gmail.com is the creator and the contact for general, privacy and security questions.
7. **Sign processor agreements** with Supabase and Vercel (both offer standard DPAs with transfer clauses), and confirm their current certifications before quoting them.
8. **Publish the policies** on the website and link them from the sign-up screen, the Settings privacy card and the website footer. (In the Test App they are bundled and readable from sign-up, sign-in and Settings → Legal.) Google OAuth verification requires the privacy policy on a verified domain you own.
9. **Website third-party requests:** fonts from onlinewebfonts.com, scripts from cdnjs and jsDelivr, and video from CloudFront expose visitors' IP addresses to those hosts. Self-host them, or keep the disclosure in Privacy §3. The BubbledotICG font license is still unconfirmed (`CREDITS.md`).
10. **Keep the documents in sync.** Any change that adds data, a destination or a provider updates `docs/DATA_SECURITY.md` *and* the Privacy Policy in the same change.

## Sources

- FTC amended COPPA Rule, compliance date: [BBB National Programs](https://bbbprograms.org/media/insights/blog/coppa-amended), [Loeb & Loeb](https://www.loeb.com/en/insights/publications/2025/05/childrens-online-privacy-in-2025-the-amended-coppa-rule), [Mondaq](https://webiis10.mondaq.com/unitedstates/privacy-protection/1790866/coppas-amended-rule-is-now-in-full-effect-what-operators-need-to-know)
- FTC edtech orders: [FTC on Edmodo](https://www.ftc.gov/news-events/news/press-releases/2023/05/ftc-says-ed-tech-provider-edmodo-unlawfully-used-childrens-personal-information-advertising), [K-12 Dive on Chegg](https://www.k12dive.com/news/ftc-order-chegg-data-security/641848), [WSGR on Chegg](https://wsgr.com/en/insights/ftc-settles-allegations-of-data-security-failures-with-edtech-company-chegg.html)
- SOPIPA: [FPF, SOPIPA at a glance](https://fpf.org/wp-content/uploads/2016/03/SOPIPA-At-a-Glance.pdf), [edlaw summary](https://edlaw.eduverse.com/docs/jurisdiction/nat/us/state/ca/sopipa/)
- FERPA and direct-to-student apps: [Promise Legal](https://blog.promise.legal/ferpa-edtech-vendors-compliance-gaps/), [Dickinson Law](https://www.dickinsonlaw.com/blogs-articles/iowa-cybersecurity-law-blog/2020/09/01/ferpa-and-online-learning-tools-protecting-student-data-when-using-online-learning-applications)
- CCPA thresholds and CalOPPA: [Feroot](https://www.feroot.com/blog/ccpa-applicability-website-california-law/), [Jackson Lewis](https://www.jacksonlewis.com/insights/navigating-california-consumer-privacy-act-30-essential-faqs-covered-businesses-including-clarifying-regulations-effective-1126), [IAPP on the CalOPPA guide](https://iapp.org/news/a/unpacking-the-california-ags-guide-on-caloppa), [Termageddon on Do Not Track](https://termageddon.com/do-not-track-caloppa/)
- 2026 state privacy laws: [TrustArc](https://trustarc.com/resource/new-in-2026-state-privacy-laws-in-indiana-kentucky-and-rhode-island/), [Hunton](https://www.hunton.com/privacy-and-information-security-law/new-u-s-state-privacy-social-media-and-ai-laws-take-effect-in-january-2026)
- GDPR Article 8 ages: [Bird & Bird](https://childreninthedigitalworld.twobirds.com/home/eu), [GDPR Art. 8 text](https://rgpd.com/gdpr/chapter-2-principles/article-8-conditions-applicable-to-childs-consent-in-relation-to-information-society-services)
- UK Children's Code: [GOV.UK guidance](https://gov.uk/guidance/child-online-safety-data-protection-and-privacy), [ESRB summary](https://esrb.org/privacy-certified-blog/the-uk-age-appropriate-design-code-childproofing-the-digital-world)
- EU AI Act Article 50: [Cooley](https://www.cooley.com/news/insight/2026/2026-08-03-eu-ai-act-transparency-obligations-take-effect-2-august-2026), [Sidley](https://datamatters.sidley.com/2026/06/24/eu-ai-act-transparency-obligations-preparing-for-compliance-by-2-august-2026/)
- Google API Services User Data Policy: [policy](https://developers.google.com/terms/api-services-user-data-policy?hl=nl), [verification requirements](https://support.google.com/cloud/answer/13464321?authuser=1)
- AI provider age terms: [Gemini API Additional Terms](https://ai.google.dev/gemini-api/terms-archive/terms_11_20_25), [Anthropic Consumer Terms](https://anthropic.com/legal/terms)
- Minors and arbitration: [California Court of Appeal, E080414](https://courts.ca.gov/opinions/archive/E080414.PDF), [Vedder Price on Garcia v. Roblox](https://vedderblog.contentpilot.net/insights-events/recent-decision-provides-roadmap-to-compel-arbitration-of-claims-asserted-by-minors/), [Eric Goldman on BF v. Amazon](https://blog.ericgoldman.org/?p=22560)
- Clickwrap: [Berman v. Freedom Financial, 9th Cir.](https://www.govinfo.gov/content/pkg/USCOURTS-ca9-20-16900/pdf/USCOURTS-ca9-20-16900-0.pdf), [Eric Goldman commentary](https://blog.ericgoldman.org/?p=23784)
