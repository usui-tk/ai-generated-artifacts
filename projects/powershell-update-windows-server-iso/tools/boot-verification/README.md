# ISO Boot Verification (Secure Boot matrix T1-T12)

Host-side harness + guest-side collectors that prove, by measurement,
whether the ISOs produced by `Update-WindowsServerIso.ps1` actually
boot in the world this project targets: firmware where the
`Microsoft Windows Production PCA 2011` CA has been **revoked**
(added to DBX) and only `Windows UEFI CA 2023` signed boot managers
are trusted.

Design basis: DESIGN-boot-verification-arc (adjudicated 2026-07-08).

## 1. Why a "revoked rig" is the only meaningful test

**Certificate expiry does not stop anything from booting.** UEFI
Secure Boot signature validation does not effectively check db
certificate validity periods; the June 2026 expiry only means
Microsoft can no longer *sign new* boot components with the 2011 CA.
An unpatched EVAL ISO installs fine on a default Secure Boot VM today
-- that observation is expected, not a test gap.

What actually blocks old media is the **deliberate revocation**:
KB5025885 Mitigation 3 places the PCA 2011 certificate into the
firmware's DBX. That is opt-in, per device. Hyper-V Gen2 stores db /
DBX **per VM** (in the VM's NVRAM / .vmgs), so applying the
mitigations *inside a guest* turns that one VM into a faithful
post-revocation environment -- the "revoked rig" (REV).

Consequence for the matrix: the STD cells (T1-T4) are lightweight
regression records; the REV cells (T5-T10) are the substance.

## 2. Test matrix

| Cell | Rig | ISO | Depth | Expected |
|------|-----|-----|-------|----------|
| T1 | STD | converted 2016 | boot | reaches-setup |
| T2 | STD | converted 2019 (fallback) | boot | reaches-setup (first-ever boot of the 2023-bootmgr + 1809-WinPE mix) |
| T3 | STD | converted 2022 | boot | reaches-setup |
| T4 | STD | unconverted 2025 | boot | reaches-setup |
| T5 | REV | converted 2016 | boot | reaches-setup |
| T6 | REV | converted 2019 (fallback) | boot | reaches-setup -- **decides the Healthy upgrade adjudication** |
| T7 | REV | converted 2022 | boot | reaches-setup |
| T8 | REV | unconverted 2025 | boot | **boot-failure** -- **the measured basis for re-opening the Server 2025 default** |
| T9 | REV | pristine EVAL ISO (any OS) | boot | **boot-failure** -- negative control; run FIRST on a fresh rig |
| T10 | REV | converted 2019 (fallback) | install | install-completes + evidence JSON (automated verdict) |
| T11 | REV | other OSes | install | optional |
| T12 | REV+SVN | any | boot | optional (Mitigation 4 additionally applied) |

Rule: **T9 before T5-T8.** A rig that boots a pristine 2011-signed
ISO is not revoked; fix the rig first.

## 3. Building the revoked rig (REV)

Prerequisite insight: the mitigations need a guest with recent
servicing. Guests installed from *unpatched* EVAL media cannot apply
them directly. The clean path doubles as an extra measurement:

1. **Install a fresh guest from THIS PROJECT'S updated Server 2022
   ISO** (Gen2, Secure Boot On, template `MicrosoftWindows`). The
   install itself is evidence that the converted media installs
   end to end.
2. Inside the guest, apply the mitigations (each step: set the
   registry value, run the scheduled task, then **reboot; repeat the
   task+reboot once more if the event log shows pending work**):

   ```text
   # Mitigation 1 -- add 'Windows UEFI CA 2023' to db
   reg add HKLM\SYSTEM\CurrentControlSet\Control\Secureboot /v AvailableUpdates /t REG_DWORD /d 0x40 /f
   powershell Start-ScheduledTask -TaskName "\Microsoft\Windows\PI\Secure-Boot-Update"
   # verify: [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match 'Windows UEFI CA 2023'

   # Mitigation 2 -- switch the boot manager to the 2023-signed one
   ... /d 0x100 /f  + task + reboot

   # Mitigation 3 -- REVOKE: add PCA 2011 to DBX (Event 1037 on success)
   ... /d 0x80 /f   + task + reboot
   # verify: [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI dbx).bytes) -match 'Microsoft Windows Production PCA 2011'

   # Mitigation 4 (OPTIONAL, cell T12 only) -- SVN update
   ... /d 0x200 /f  + task + reboot
   ```

3. Run `Test-SecureBootRigState.ps1` inside the guest; it must print
   `RIG READY` (db has 2023 **and** dbx carries the PCA 2011 cert).
4. Shut the rig VM down and run **T9**.

Notes:

- **Checkpoint experiment (record the answer!):** take a checkpoint
  *before* Mitigation 3. UEFI variables live in the VM's .vmgs, so
  restoring the checkpoint MAY roll the NVRAM back to un-revoked --
  if it does, one VM can flip between worlds. Record the observed
  behaviour in the ledger notes either way; it decides whether we
  keep long-lived rigs or rebuild.
- Mitigation 3 is otherwise **irreversible by design** while Secure
  Boot is enabled. Treat the rig as consumable; `Export-VM` a copy
  first if you want spares.
- Before T10, checkpoint or export the rig: the install-depth cell
  wipes whatever disk 0 is. Recommended T10 shape: detach the rig's
  OS VHDX, attach a fresh blank 64 GB VHDX as the only hard disk,
  attach the EVIDENCE data VHDX, then run the harness. The revoked
  NVRAM survives disk swaps (it is VM-scoped, not disk-scoped); it
  does NOT survive deleting/recreating the VM.

## 4. Running cells

```powershell
# STD boot cells (ephemeral VM per run):
.\Invoke-IsoBootVerification.ps1 -Cell T2 -IsoPath D:\out\WS2019_Updated.iso

# REV boot cells (existing rig VM, must be Off):
.\Invoke-IsoBootVerification.ps1 -Cell T6 -IsoPath D:\out\WS2019_Updated.iso -RigVmName SbRevRig01

# T10 (unattended install + collection); build the data VHDX once:
.\New-EvidenceDataVhdx.ps1 -Path D:\rig\evidence.vhdx -ImageIndex 2 -AdminPassword 'BootVerify#2026'
.\Invoke-IsoBootVerification.ps1 -Cell T10 -IsoPath D:\out\WS2019_Updated.iso -RigVmName SbRevRig01 -DataVhdxPath D:\rig\evidence.vhdx
```

Verdicts:

- **boot-depth cells are operator-confirmed**: the harness saves
  console screenshots at 30/90/180 s under `results\<cell>_<stamp>\`
  and records `Outcome=pending-operator` in `results\ledger.jsonl`.
  `VM State = Running` is *never* a verdict (a VM sits at a firmware
  failure screen in the Running state). Setup UI on the screenshot =>
  `reaches-setup`; a Secure Boot / "no operating system" firmware
  screen => `boot-failure`. Edit the ledger entry's Outcome, or note
  it when returning results.
- **T10 is automated**: the unattended install runs the collector at
  first logon and powers the VM off; `installed_evidence.json`
  appearing on the EVIDENCE VHDX is the verdict.

Return package after a matrix run: `results\` (ledger + run
directories with screenshots + collected evidence), zipped.

## 5. What the results decide (adjudication mapping)

| Result | Decision |
|--------|----------|
| T6 (and T2) reach Setup | 2019 fallback shape upgraded from Warning to Healthy in P12 |
| T6 fails | fallback design re-opened (WinPE replacement paths investigated) |
| T8 boot-failure | measured basis to flip the Server 2025 default to convert (re-open r11.55) |
| T8 reaches Setup | current 2025 default stands; basis recorded |
| T10 completes + evidence sane | end-to-end proof for the 2019 deliverable |

Triage note: if T6/T10 fail while T5/T7 pass, the first suspect is
`boot.stl` (the converted media carries the one sourced from
install.wim). Re-run T6 with `EFI\Microsoft\Boot\boot.stl` removed
from a scratch copy of the extracted media, then with the boot.stl
taken from a serviced boot.wim of another OS, and record both.

## 6. Files

| File | Runs on | Purpose |
|------|---------|---------|
| `Invoke-IsoBootVerification.ps1` | host | drive one matrix cell; screenshots; ledger |
| `New-EvidenceDataVhdx.ps1` | host | build the EVIDENCE VHDX (autounattend + collector); **the answer file wipes disk 0 -- disposable VMs only** |
| `Export-InstalledSystemEvidence.ps1` | guest | post-install evidence JSON (vocabulary aligned with `inspection_post.json`) |
| `Test-SecureBootRigState.ps1` | guest | rig verdict: db/dbx parsed, `RIG READY` gate |
| `BootVerification.Common.ps1` | both | shared pure functions (ESL parser, RGB565->BMP, cell map, ledger) |
| `autounattend-template.xml` | (template) | tokenised unattended answer file |

Known limits (also stated in the evidence JSON): the guest-side boot
manager signature uses `Get-AuthenticodeSignature` (can under-report
embedded PCA2023 signatures via the catalog path; db/dbx state plus
the boot result are the primary evidence). Hyper-V's virtual UEFI is
faithful for db/DBX chain validation but is not OEM firmware; a
one-off spot check on real revoked hardware remains desirable.

Estimated effort: first run incl. rig build ~half a day; re-runs 1-2 h.
