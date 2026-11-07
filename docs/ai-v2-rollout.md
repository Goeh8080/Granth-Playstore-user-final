# AI v2 app integration (reviewed backend7cbcb93 §25)

Status: app entry wired and offline tested; backend contract is LOCAL, not deployed. `kAiV2RolloutEnabled=false` in `lib/ai/quiz_v2.dart`. No v2 production traffic until an explicit reviewed rollout changes this gate and the real backend advertises capabilities. Do not infer deployment or verified Google/device behavior from mocks.

## App entry / APIs
- `#/ai` → `AiPanel` header `ai-gyan` → `_gyan(context)` in `lib/screens/ai_screen.dart` → capability-gated `_QuizV2Sheet`. Router/Exit/Back untouched; closing the sheet preserves its owner-scoped pending operation.
- `GET /ai/capabilities`;404/unavailable/rollout-off uses existing legacy behavior. Known disabled quiz never bypasses the admin setting via legacy.
- Exact protected POST routes: `/ai/quiz/session`, `/ai/quiz/session/{session_id}/next`, `/ai/quiz/session/{session_id}/attempt`. Bodies schema2, stable request IDs, no IP/client UID proof. Header `Authorization: Bearer <Firebase Google ID token>` plus `X-App-Key`. No v2 payload to `/ask`.
- Three sources: वेद से / पुराण से / सारे ग्रंथ. Locked until a new session. Only public single-choice question+options; correctness is absent until submit. All incorrect options red, correct green after authoritative option_results. No images/answer-key/provenance/explanation before submit. Exhausted differs from503; never falls back to another source. Backend lifetime per-owner stable-question ledger is authoritative, including across devices. The bounded local ID guard is defensive only.
- Lost requests replay immutable IDs/bodies after restart. Bound410 is terminal for that ID; advancing uses a new ID. Owner changes hide visible state/drop late replies. Logout retains isolated same-owner unsent drafts for durable retry; account deletion clears that owner's drafts/session/report-key cache. No tokens persisted in drafts.

## Flags
`AnswerBubble` thumbs-down/correction uses normal_chat; `_QuizV2Sheet` reports use gyan_charcha with the server-owned attempt/question/revision only. POST `/ai/flags` schema2, stable client_report_id/kind/context. No quiz prose or invented attempt IDs. Historical legacy quiz messages cannot be relabeled as v2 normal chat; they need a new server-owned discussion. V1 remains v1 when v2 is unavailable.

Owner-bound immutable outbox persists queued status; only202 plus positive server report ID marks sent. Conflicts/outages retain the payload. One disabled context never blocks an enabled context. Queue bounded50; no pending report is evicted. Foreground catalog-sync hook retries eligible reports; immediate explicit flag submission attempts a flush. Existing remote flags master switch remains respected. Public limits: question500, answer/correction2000, reason300 codepoints; total8192UTF8 bytes. Oversize is not falsely marked queued; future full-answer reference support must use a real server contract, not an invented API.

## Verification / rollout gaps
Offline HTTP and actual-entry widget tests cover sources, question/grade projection, Google-header mocks, owner/logout hiding, immutable retries/restart/410, no answer leaks, context separation and queued→ACK status at320dp/text1.3. These are not real Firebase verification or live delivery tests.

Backend0015/deployment, bank/provenance readiness, capabilities/admin enablement, production app gate activation and real Google/two-device/exhaustion/flags acceptance remain pending. Navigator interpret, Tatv normal-answer suppression consumer and private notifications remain unavailable/untouched. No local release build or release replacement in this milestone.
