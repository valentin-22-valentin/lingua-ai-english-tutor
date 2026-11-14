# Verification — 2026-11-10

| Check | Result |
| --- | --- |
| Python regression suite | 138 passed |
| PostgreSQL/PGlite transaction suite | 25 passed |
| Flutter controller/widget suite | 57 passed (61 after the 2026-11-15 re-run) |
| Flutter analysis | No issues found |
| Demo web release build | Successful |
| Curriculum | 103 lessons validated; all 103 × 8 prompts constructed in tests |
| Live synthetic tutor cases | 10/10 task-grading checks passed |
| Live synthetic A1 journey | 8/8 tasks completed in 9 model calls |
| Live placement | Greeting + 10 answers, completed with a provisional level |
| Live journal | Real model correction and Hungarian follow-up discussion succeeded |
| Re-run 2026-11-15 | Python 138, SQL 25, Flutter 61 passed; analysis clean; course audit OK |
| Release browser smoke test | Mobile drawer → history, repeated drawer navigation; no browser errors |

The release regressions cover the observed drawer crash, clearing failed placement
state before beginner lessons, restoring full chat transcripts, recovery from a
failed send, pagination and ownership of history, and ignoring late private
responses after logout. SQL upgrade tests preserve old messages while closing
sessions that no longer belong to the current lesson. Fresh installation is
applied twice to test repeatability.

The restarted live app also successfully listed historical sessions and
displayed saved learner/teacher messages. A word-internal encoding defect in
new translated labels found in this run was corrected in the UTF-8 resources and
covered by a dedicated five-locale regression. The final web demo was rebuilt.

The command-line real-model checks used synthetic examples, a 200-token cap per
response, and no cloud database writes. Explicit German and French explanation requests were also
checked after adding language instructions to the structured text field. These
samples establish observed behavior, not general teaching accuracy or guaranteed
prompt-injection resistance. CEFR placement remains a provisional practice level.
[Structured Outputs reference](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat).

After schema release 9 was installed, live readiness returned ready. In the
authorized test account, browser checks completed an A1 session at 8/8, recorded
its completion and unlocked only the next lesson. The run exposed a help request
incorrectly accepted as comprehension evidence; the grading instructions now
separate teacher actions from learner evidence. A subsequent real-model help
request remained unpassed and received the example with its Hungarian meaning.
The final ten-case model regression also passed 10/10. The earlier browser run is
not presented as eight flawless grading decisions.

The real browser journal test saved a fictional entry, corrected "Yesterday I go"
to "Yesterday I went", and saved a Hungarian follow-up discussion. The completed
lesson appeared in conversation history.

This report does not claim a physical-device microphone test, Docker run,
GitHub-hosted CI run, or learning-outcome validation.

Run the evaluation commands in README.md to reproduce the public cases and lesson journey.
