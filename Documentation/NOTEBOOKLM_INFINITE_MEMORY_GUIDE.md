# 🧠 NotebookLM Infinite Memory for Antigravity

This guide explains how **Google NotebookLM** is integrated into **Antigravity (JARVIS)** as a persistent, multi-million token external memory layer.

---

## 🌟 Why Infinite Memory?

Standard LLM sessions suffer from **context amnesia** — every new session forgets previous architectural discussions, user preferences, bug investigations, and milestone notes.

With **NotebookLM Infinite Memory**:
- **Multi-Million Token Long-Term Retention**: Grounded in Google NotebookLM's high-capacity knowledge index.
- **Fast Semantic Recall**: Antigravity automatically queries your memory notebook with source citations before beginning complex work.
- **Automated Wrap-Up Snapshots**: At the end of a session or feature build, Antigravity records a structured snapshot directly into NotebookLM.
- **Audio Overviews**: Generate spoken deep-dive audio podcasts summarizing your project's history and architecture at any time.

---

## 🚀 Setup & Linking a Notebook

### Step 1: Create your Memory Notebook
1. Go to [notebooklm.google.com](https://notebooklm.google.com).
2. Click **Create new notebook** (e.g., name it `Kissa Focus - Project Memory` or `JARVIS Global Memory`).
3. (Optional) Ingest any existing documentation, architecture notes, or guidelines as initial sources.

### Step 2: Get the Share Link
1. Click the **Share** button in the top right corner of the notebook.
2. Change access to **"Anyone with the link"** (Viewer or Editor).
3. Click **Copy link**.

### Step 3: Register with Antigravity
Simply paste the link into the chat with Antigravity:
> *"Register this notebook for Infinite Memory: `https://notebooklm.google.com/notebook/...`"*

Antigravity will execute `add_notebook` and `select_notebook` to make it your active memory notebook.

---

## 🔄 Daily Workflow

### 1. Context Recall (Beginning of Task)
Ask Antigravity to recall past decisions:
- *"Check our NotebookLM memory for how we designed the Supabase backup synchronization."*
- *"What were the key decisions made regarding the ferrofluid UI animation?"*

### 2. Session Wrap-Up (End of Task)
Simply prompt Antigravity:
- *"Wrap up this session and save a snapshot to NotebookLM memory."*

Antigravity will format a structured snapshot (Changes, Decisions, File Mappings, Next Steps) and ingest it using `add_source`.

### 3. Generate Audio Overview Podcast
- *"Generate an Audio Overview of our project memory notebook and save it to the project."*

Antigravity will trigger `generate_audio`, monitor generation, and download the audio file directly to your workspace.

---

## 🛠️ MCP Tool Reference

| Tool | Purpose |
| :--- | :--- |
| `list_notebooks` | List all registered memory notebooks. |
| `select_notebook` | Switch the active memory notebook. |
| `ask_question` | Query memory with grounded semantic retrieval & citations. |
| `add_source` | Save a new snapshot or document into memory. |
| `generate_audio` | Initiate an AI audio overview podcast of the notebook. |
| `download_audio` | Save the generated podcast to disk. |
| `get_health` | Verify authentication and connection health. |
