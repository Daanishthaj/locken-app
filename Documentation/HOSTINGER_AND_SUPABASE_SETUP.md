# Locken — Hostinger & Supabase Setup & Production Guide

This guide covers everything required to deploy the **Locken Web Platform** onto **Hostinger Web Hosting** and connect your **Supabase Database** for real-time waitlists, cloud profiles, and focus session sync.

---

## 1. 🗄️ Supabase Setup (5 Minutes)

### Step 1: Create a Supabase Project
1. Go to [https://supabase.com](https://supabase.com) and create a free account or log in.
2. Click **"+ New Project"**, name it `Locken`, and set a strong database password.
3. Select the region closest to your primary user base (e.g. `US East`, `EU Central`).

### Step 2: Apply Database Schema & Migrations
1. In your Supabase Dashboard, click the **SQL Editor** tab from the left sidebar.
2. Click **"+ New Query"**.
3. Open `supabase/migrations/20260901_initial_schema.sql` in this repository, copy the full contents, and paste it into the Supabase SQL editor.
4. Click **Run** (Cmd + Enter).
5. All 4 core tables (`waitlist_subscribers`, `profiles`, `focus_sessions`, `notes`) and Row-Level Security (RLS) policies are now live!

### Step 3: Copy API Credentials
1. In Supabase, go to **Project Settings** → **API**.
2. Copy:
   - **Project URL** (e.g. `https://xyzcompany.supabase.co`)
   - **Project API Keys** → `anon` `public` key (e.g. `eyJhbGci...`)
3. In your `web/` folder, create a `.env` file:
   ```env
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=your-anon-public-key
   VITE_SITE_URL=https://locken.app
   ```

---

## 2. 🚀 Hostinger Web Hosting Deployment

### Option A: Automated Build & Upload via Hostinger File Manager (Recommended)
1. In your terminal, run the deploy script:
   ```bash
   ./deploy-hostinger.sh
   ```
   *This automatically builds the production Vite bundle and packages `locken-hostinger-build.tar.gz`.*
2. Log into your **Hostinger hPanel** (`hpanel.hostinger.com`).
3. Click **Websites** → select your domain → click **File Manager**.
4. Double-click to open `public_html/`.
5. Click **Upload Files** (top right icon) and upload `locken-hostinger-build.tar.gz`.
6. Right-click the `.tar.gz` archive in File Manager and choose **Extract** → Extract to `/public_html`.
7. Done! Your site is live with HTTPS, Gzip, Brotli, and full Single Page App routing!

### Option B: Hostinger Git Deployment (Continuous Deployment)
1. In **Hostinger hPanel**, navigate to **Git** under Advanced settings.
2. Link your GitHub repository.
3. Set the branch to `main` and build directory to `web/dist`.

---

## 3. 🛡️ Security & Performance Verification Checklist
- [x] **Zero-Telemetry Default**: If Supabase is unconfigured, the app & website automatically fall back to 100% on-device local storage.
- [x] **Row-Level Security (RLS)**: Anonymous visitors can only insert valid emails into the waitlist; all user sessions and notes are strictly protected by user authentication IDs.
- [x] **Hostinger Security Headers**: `.htaccess` enables strict Content Security Policy (CSP), `X-Frame-Options: DENY`, and `X-Content-Type-Options: nosniff`.
- [x] **Asset Caching**: CSS/JS bundles have 1-year immutable caching headers with automated cache-busting hashes on new releases.
