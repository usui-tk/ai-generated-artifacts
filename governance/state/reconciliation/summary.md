# Proposals ledger - open items (regenerated view)

- open: 3 / decided: 0 / ledger records: 3

| proposal_id | unit_id | first_seen | tier/status |
|:--|:--|:--|:--|
| `prop-20260808T182909Z-179ea7d23f7e5d38` | `pwsh.helper.start-debugtrace` | 20260808T182909Z | pending-decision |
| `prop-20260808T182909Z-31576b5b60965548` | `pwsh.helper.debugtrace-writejsonlline` | 20260808T182909Z | pending-decision |
| `prop-20260808T182909Z-805d4fbeab72da0b` | `pwsh.helper.enable-debugtracefileoutput` | 20260808T182909Z | pending-decision |

Decide with: `python3 quality-tools/reconciliation-loop/coldloop.py decide --proposal-id <id> --status accepted|rejected --auth <ref>` - decisions are APPENDED records; an accepted proposal then follows the normal human-gated mutation flow (promote / restamp + the full battery).
