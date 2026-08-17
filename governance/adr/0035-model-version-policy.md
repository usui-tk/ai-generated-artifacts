---
id: 0035
title: model-version-policy
status: accepted
date: 2026-08-18
supersedes: []
superseded_by: null
governs: []
---

<!-- AI read-contract: authoritative for when a tool's emitted-model version advances,
     for what a shape fingerprint can and cannot prove, and for how an artefact derived
     from a tool's output identifies the build that produced it. Read when changing the
     emitted model, the acceptance baselines or the derived-cache format of
     quality-tools/powershell-symbol-surveyor/; not loaded every session. -->

# 0035 — When the model version advances, and what a shape fingerprint proves

## Context

ADR 0034 made a change of emitted-model shape a gate failure and then stopped
short on purpose. Its sixth decision says a shape change forces an adjudication
rather than a particular answer, and states plainly that it sets no version
policy — it makes the absence of one detectable. This decision supplies the
policy, and it does so against measurement rather than against the intuition
that a version ought to move when something changes.

**What the absence had cost.** Every committed revision of the surveyor was
re-run against the pinned blob and its emitted key-path set fingerprinted. The
default materialisation walks `07425f04` → `3a80d84c` → `1610f95a` →
`6234f0a7` → `da702e66`: four changes of shape, one of them purely
destructive, across seven committed revisions that all declare
`model_version = "1"`. `pss_version` is `0.1.0` in all seven, including the two
revisions that changed what the extractor reports. Neither constant had moved
since the tool was first committed.

**What a shape fingerprint cannot see.** The ADR 0034 extractor fixes changed
which fact code the extractor attaches to a reference without adding or
removing a single key path: measured at the pinned generation, nine records
move between `PSS2003` and `PSS2002` while both fingerprints stay at
`da702e66` and `020e2592` (across the corpus the recorded net movement is 2,302
records). A model produced before that fix and a model produced after it
therefore both satisfy §5.5's equality condition and would be compared —
manufacturing, from a corrected tool, exactly the false deltas §5.5 exists to
prevent. Shape identity is not model identity, and treating one as the other is
what §5.5 has been doing.

**Where the same reasoning had already leaked.** The raw model caches that are
derived from the tool and kept outside the repository had adopted the shape
fingerprint as the discriminator between cache generations, on the assumption
that a fingerprint identifies the build. It does not, and the change that
motivated adopting it is precisely a change it cannot see.

**A shape figure without a basis is the defect ADR 0034 removed, recurring
inside ADR 0034.** That ADR records the drift as *four shape changes, ten of
them field removals*. The removal step removes **eleven** key paths when
measured against the pinned blob, of which two are restored later under the
`closure-sets` axis, leaving **nine** unrecoverable under any axis; the same
code change measured against an early generation (entry `0001`, blob
`7783700a`) removes **thirteen**, because two of the paths are optional fields
that a smaller script never populates. Ten is reproduced by no basis. The
figure is not wrong by carelessness — it was recorded without stating what it
was measured against, which is the condition ADR 0034 forbids for acceptance
figures and did not extend to figures about the model itself.

## Decision

**1. The model version advances whenever the model emitted for a fixed input
can differ.** Shape and content are both in scope: a new or removed key path
advances it, and so does a change to which records, codes, roles or counts the
extractor produces for input it already handled. The test is stated in terms of
the emitted artefact rather than the size of the code change, because that is
what §5.5's consumers compare.

**2. The version is not renumbered retroactively.** `"1"` names six mutually
incompatible builds. Models already emitted cannot be re-labelled, so the
history is recorded rather than rewritten: two models both carrying `"1"` are
not evidence of comparability, and §5.5 says so. The first advance is made by
the first patch that changes what the model emits; this decision, which changes
no emitted model, does not make it.

**3. `pss_version` advances under SemVer on every landed change, and is decided
separately.** The surveyor is the only tool in `quality-tools/` whose version
has never moved while its behaviour has, and a version that never moves carries
no information. The two constants answer different questions — *which build* and
*which model contract* — and neither substitutes for the other.

**4. The shape fingerprint is a check over observed key paths, not a schema, and
is labelled as such.** It records the shape the pinned generation reaches, so a
new optional field that the pinned generation never populates would not move
it — the mechanism by which the same code change measures eleven removals at one
basis and thirteen at another. The remedy is a **declared** key-path schema,
checked in both directions (every emitted path is declared; every declared path
is either exercised at the pin or marked data-dependent), which is §13.2's
enumerated-constant reachability rule applied to the model. It is recorded as
owed rather than built here.

**5. An artefact derived from the model identifies its producing build by a
baseline digest, never by the model version or a shape fingerprint alone.** The
digest is taken over the acceptance block the tool re-derives from the pinned
blob, so any change to a measured quantity changes it. A derived artefact that
cannot state which build produced it is not evidence, whatever it contains; the
contract is §14.4.

**6. A figure about the model states the basis it was measured against.** ADR
0034 required this of acceptance figures. It is extended here to shape figures —
key-path counts, added and removed sets, fingerprints — because they are
data-dependent in exactly the way acceptance figures are, and a bare count is
therefore unfalsifiable in the same way.

## Consequences

`compare` is now specified against a version that means something. When it is
built (S3), a `model_version` match is a statement about the model contract
rather than about the tool's key paths, and §5.5's guarantee is one the
mechanism can actually make.

The next patch that changes the emitted model is the one that advances the
version, and the baseline gate is what forces the question: any change to shape
or to a B.8 figure fails it, and clearing it requires re-stamping B.8, at which
point the version decision is made and recorded. The enforcement is a
consequence of an existing gate rather than a new one.

Two holes are now named rather than closed, which is the honest state. The
fingerprint's observed-not-declared basis (decision 4) and the absence of an
automated check that a version decision was in fact taken are both recorded in
§13.2 as owed. Naming them is what ADR 0034's rule requires of a check that
does not yet exist; leaving them unnamed while the fingerprint reads as a
schema is what this ADR exists to stop.

The derived caches gain a contract they did not have. Their format was governed
by convention in an out-of-repo handoff document, which is how the fingerprint
came to be used for a job it cannot do; §14.4 puts the header requirement where
the tool's other contracts are.

The cost is that the version will move more often than a shape-only rule would
move it, including for changes that add no field. This is accepted: a version
that moves when the artefact changes is doing the work §5.5 asks of it, and the
alternative has already been measured — six builds, one number, and a
comparison that would have reported a fixed tool as 2,302 source changes.
