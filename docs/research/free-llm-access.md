# Free LLM access for the editor

Research note, 22 November 2026. Question: how can the paper's editor call a
model from any server, without paying and without a personal browser login?

## Ranked answer

1. **Google Gemini free tier** — `https://generativelanguage.googleapis.com/v1beta/openai/`,
   model `gemini-3.5-flash-lite` (or another Flash model). No card, 1M-token
   context and 65,536 output tokens, 250K tokens/minute, 500 requests/day. One
   call can hold the whole 25k-token brief and write all 21 stories at the
   paper's real word budgets. Get a key at `aistudio.google.com/apikey`. Free
   tier prompts may be reviewed and used to improve Google products; the paper
   only sends already-public article text. EEA/UK/CH servers may be restricted
   to paid API access.
2. **OpenRouter free models** — `https://openrouter.ai/api/v1`, model
   `nvidia/nemotron-3.5-lightning:free` (1M context, 65k output). Account, no
   card, 50 free requests/day. Good fallback; free model IDs churn, so check
   `GET /models` at deploy time.
3. **Keyless emergency** — `mix frontier.keyless` with a provider such as
   `https://blockrun.ai/api/v1`, model `nvidia/nemotron-3.5-bolt`,
   `FRONTIER_LLM_KEYLESS=1`, `FRONTIER_LLM_REASONING_EFFORT=low`. No signup.
   BlockRun's free lane trims requests over 128 KB, so the paper is written one
   section at a time in a plain line format. The model writes 50–65 word
   summaries rather than the paper's 80–100, so the keyless edition runs
   shorter (roughly 3–7 minutes) and is honest about it in the read time.

Ruled out: Groq free tier (8K TPM cannot hold one brief), Cerebras trial (card
required), GitHub Models (retired 30 Jul 2026), OVH anonymous lane (2 RPM,
shared and often 429), Pollinations (one model, ~1500 output tokens, often
spent on reasoning), browser automation of ChatGPT/Gemini/Claude (needs a
personal login, cannot run on a server, fragile and against consumer terms).

## Environment for the recommended setup

```bash
export FRONTIER_LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/
export FRONTIER_LLM_MODEL=gemini-3.5-flash-lite
export FRONTIER_LLM_API_KEY=<free key>
unset FRONTIER_LLM_KEYLESS
# one-shot: mix frontier.daily --day YYYY-MM-DD, then mix frontier.publish
```

For the keyless fallback use `FRONTIER_LLM_KEYLESS=1`, `FRONTIER_EDITOR=keyless`
and `mix frontier.keyless`; no key variable is needed.

Source: primary provider docs and pricing pages where available; a few limits
(Google's exact free quotas, LLM7's) come from third-party live-probe
directories and should be rechecked before relying on them.
