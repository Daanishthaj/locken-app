# Competitor complaints: top 10 (step 1, "collect")

**Collected:** October 18, 2026
**Source:** US App Store reviews, the 500 most recent per app (Apple's public review feed), for 12 focus and blocker apps: Opal, Freedom, Forest, ScreenZen, one sec, Structured, Flow, BlockSite, Brick, ClearSpace, Jomo and Focus To-Do.
**Sample:** 5,736 reviews, of which 1,728 are 1 to 3 stars. Counts below are of those 1,728.

**How the counting works:** each review was matched against keyword patterns for each complaint, so one review can count toward several complaints. Treat the numbers as a ranking, not exact figures. Paraphrases only; no review is copied here. Raw data and patterns are in `build/reviews/` (git-ignored).

**Caveat:** most of these apps are iPhone-first. Complaints about iPhone Screen Time limits don't all carry over to a Mac app. Reddit and the Mac App Store were not checked yet.

| # | Complaint | Reviews | Mostly about | What people say | Locken today |
|---|---|---|---|---|---|
| 1 | Paywalls and subscriptions | 477 (28%) | Forest 78, Freedom 64, BlockSite 57, Opal 56 | The free tier blocks only one app or locks basic settings like timer length. People who paid once were moved to a subscription. Trials renewed without a reminder, and subscriptions were hard to cancel. | **Strong.** Free, no card, no trial. |
| 2 | Bugs, freezes and crashes | 335 (19%) | Opal 123, Forest 42, ClearSpace 38, Freedom 36 | The app freezes or won't open, gets laggy, or drains the battery after an update. | **No claim.** Show it working instead of promising "no bugs". |
| 3 | "The update ruined it" (redesign) | 278 (16%) | Forest 125, Opal 114 | Forest's Sept/Oct 2026 redesign: slower time picker, favorites gone, more taps to start. Opal's redesign: scores nobody wanted, harder to unblock, lag. | **Partial.** Starting a session is one goal and one button. Lesson: don't break workflows people rely on. |
| 4 | Too easy to get around | 106 (6%) | Opal 21, Freedom 12, BlockSite 12, Brick 11 | Delete the app, turn off its Screen Time access, restart the phone, or force-close it (one Flow review says this undoes its Mac "Commitment Mode"). | **Partial.** Commitment mode puts a countdown before pausing, ending, quitting or turning off the Shield. **Gap:** force-quitting Locken (Activity Monitor or Force Quit) ends the session and the blocking, and the session isn't restored when Locken reopens. |
| 5 | Confusing, cluttered, too many steps | 100 (6%) | Opal 38, Forest 22 | Overwhelming screens, too many taps for simple things. | **Partial.** Locken has a lot of features too; keep the start flow short. |
| 6 | Features taken away | 90 (5%) | Brick 37, Forest 27, Opal 13 | Brick removed timed sessions (schedules only now). Forest removed favorites. | **Strong for Brick's complaint.** Timed sessions plus a free menu bar timer. |
| 7 | No Mac, desktop or sync | 86 (5%) | Focus To-Do 27, Flow 21, Structured 12, Freedom 7 | No sync between Mac and phone, broken desktop versions, no Windows. | **Strong on desktop.** Native Mac app, plus Windows. No phone app. |
| 8 | Blocks unreliably | 55 (3%) | Opal 19, Freedom 9, Brick 8, BlockSite 8 | Blocks apps that aren't on the list, locks people out at the wrong time, or doesn't unlock after a session. | **Partial.** Closes only games, social and YouTube by default; users choose what else to block or unblock. |
| 9 | Ads | 52 (3%) | Forest 22, one sec 7, ClearSpace 7 | Ads inside a focus app. | **Strong.** No ads. |
| 10 | Support never answers | 44 (3%) | Focus To-Do 11, Brick 8 | Emails ignored, no way to reach a person. | **Partial.** In-app feedback goes straight to you; answering it is the advantage. |

**Just outside the top 10**
- **Privacy, VPN and spam (39):** mostly Freedom (20). Its VPN profile clashes with people's own VPN; some got spam emails after signing up. Locken needs no VPN and no Full Disk Access, and its data stays on the Mac. **Strong.**
- **Gamification nobody asked for (37):** Forest 18, Opal 13 (scores, gems, coins).

## Best openings for Locken
1. **Paywalls (#1):** free, no card. Biggest complaint, clearest answer.
2. **No Mac or Windows (#7) plus ads (#9) plus privacy:** a desktop focus app with no ads, no VPN and nothing leaving the Mac.
3. **Brick's removed timer and Forest's redesign (#3, #6):** timely. These users are looking for something else right now.
4. **Bypass (#4):** commitment mode is a real answer, but close the force-quit gap before making a video about it.
