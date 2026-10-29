// Preview-only stand-in for Tauri's invoke() so the app runs in a normal browser. Never shipped.
const calls = (window.__lockenCalls = []);
export async function invoke(command, args) {
  calls.push({ command, args });
  switch (command) {
    case 'ai_key_status': return window.__aiKey ?? null;
    case 'ai_save_key': { const key = String(args?.key || ''); const name = key.startsWith('sk-ant-') ? 'Claude' : key.length >= 20 && key.startsWith('sk-') ? 'ChatGPT' : null; if (!name) throw "That doesn't look like a Claude (sk-ant-…), ChatGPT (sk-…) or Gemini (Google AI Studio) key."; window.__aiKey = name; return name; }
    case 'ai_remove_key': window.__aiKey = null; return null;
    case 'ai_rephrase': await new Promise((r) => setTimeout(r, 600)); return 'Complete 15 practice problems for Calculus Chapter 4';
    case 'ai_milestones': await new Promise((r) => setTimeout(r, 600)); return ['Review Chapter 4 examples', 'Solve problems 1-8', 'Solve problems 9-15', 'Check answers and fix mistakes'];
    case 'ai_week_digest': await new Promise((r) => setTimeout(r, 600)); return '### Due this week\n- **Soon:** Unit 1 Review (Precalculus), due Tue 11:59 PM\n- Lab report (Biology), due Thu 9:00 AM\n### Busy days\n- Tuesday: two deadlines on one day.\n### Plan\n- Monday after school: 45 minutes on Unit 1 Review.\n- Wednesday: draft the lab report <b>not html</b>.';
    case 'ai_assistant': await new Promise((r) => setTimeout(r, 700)); return /start|session/i.test(args?.message || '') ? '{"say":"Let\'s do it. Want me to start 25 minutes on your Unit 1 Review?","action":{"type":"start_session","goal":"Finish the Unit 1 Review","minutes":25}}' : '{"say":"Start with the Unit 1 Review, since it\'s due tomorrow. A 25-minute session should get most of it done.","action":null}';
    case 'voice_key_status': return Boolean(window.__voiceKey);
    case 'voice_list': return window.__voiceKey ? [{ id: '6i4Eb1eUSagmAhMPqhYS', name: 'Hype' }, { id: 'rFtEb2MlDt7EXDbMtvop', name: 'Calm' }] : [];
    case 'voice_save_key': if (String(args?.key || '').length < 20) throw "That doesn't look like an ElevenLabs API key."; window.__voiceKey = true; return [{ id: '6i4Eb1eUSagmAhMPqhYS', name: 'Hype' }, { id: 'rFtEb2MlDt7EXDbMtvop', name: 'Calm' }];
    case 'voice_remove_key': window.__voiceKey = false; return null;
    case 'voice_speech': throw 'preview';
    case 'canvas_status': return window.__canvas ?? null;
    case 'canvas_unlink': window.__canvas = null; return null;
    case 'canvas_link_feed': throw 'That link didn\'t return a Canvas calendar feed.';
    case 'canvas_link_token':
    case 'canvas_refresh': {
      if (command === 'canvas_link_token') {
        if (!String(args?.address || '').includes('.')) throw "Enter your school's Canvas address, for example school.instructure.com.";
        window.__canvas = { method: 'token', host: 'school.instructure.com' };
      }
      await new Promise((r) => setTimeout(r, 400));
      const day = (n, h) => new Date(Date.now() + n * 86400000).toISOString().replace(/T.*/, `T${h}:00:00Z`);
      return { kind: 'api', items: [
        { id: 'api-1', title: 'Unit 1 Review', course: 'Precalculus', due: day(1, '23') },
        { id: 'api-2', title: 'Lab report: enzymes', course: 'Biology', due: day(3, '17') },
        { id: 'api-3', title: 'Spanish vocab quiz', course: 'Spanish II', due: day(5, '15') },
      ] };
    }
    case 'user_name': return 'mohammed';
    case 'now_playing': return window.__previewTrack ?? { title: 'Weightless', artist: 'Marconi Union', playing: true, cover: '' };
    case 'media_play_pause': if (window.__previewTrack !== null) window.__previewTrack = { ...(window.__previewTrack || { title: 'Weightless', artist: 'Marconi Union', cover: '' }), playing: !(window.__previewTrack?.playing ?? true) }; return null;
    case 'load_session': return { access: window.__aal2 ? `x.${btoa(JSON.stringify({ aal: 'aal2' }))}.y` : 'preview-access', refresh: 'preview-refresh' };
    case 'save_session': if (String(args?.access || '').startsWith('x.')) window.__aal2 = true; return null;
    case 'default_blocked_apps': return ['Discord', 'WhatsApp', 'Telegram', 'Steam', 'Roblox', 'Minecraft'];
    case 'running_apps': return [{ exe: 'spotify.exe', name: 'spotify' }, { exe: 'notion.exe', name: 'notion' }];
    default: return null;
  }
}
