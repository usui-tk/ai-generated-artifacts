"""Python-side driver for the PowerShell TestHarness REPL.

The PowerShell script exposes a ``-Action TestHarness`` mode that loads
all function definitions, then reads JSON requests from stdin and emits
JSON results on stdout. This module is the Python counterpart: it
spawns one ``pwsh -Action TestHarness`` process per ``PSSession``,
writes one JSON request per line, and parses the JSON response.

Why a long-lived child process: starting ``pwsh`` and dot-sourcing the
7,000-line script takes 1-2 seconds. Spawning one per assertion would
add tens of seconds of overhead per test run; keeping it alive lets
hundreds of assertions reuse the same loaded session.

Lifecycle: ``PSSession`` is a context manager. Use it as::

    with PSSession(script_path) as ps:
        result = ps.invoke('Get-CatalogQueryTemplate',
                           OsVersion='Server2022', PatchMonth='2026-05')
        assert 'comma' not in result['TitleTokens'][0]
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, Optional


class PSHarnessError(RuntimeError):
    """Raised when the TestHarness REPL returns an error or fails to start."""


class PSSession:
    """A long-lived ``pwsh -Action TestHarness`` subprocess.

    Not thread-safe: a single ``PSSession`` must be driven from one
    Python thread at a time (the request/response protocol is
    line-oriented and stateful per process).
    """

    def __init__(self, script_path: str | os.PathLike) -> None:
        self.script_path = Path(script_path).resolve()
        if not self.script_path.exists():
            raise PSHarnessError(f'Script not found: {self.script_path}')
        self._proc: Optional[subprocess.Popen[str]] = None

    def __enter__(self) -> 'PSSession':
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def start(self) -> None:
        if self._proc is not None:
            return
        # Use pwsh if available, otherwise PowerShell. On Linux/Mac
        # only pwsh exists; on Windows both work but pwsh is preferred.
        pwsh_bin = self._find_pwsh()
        cmd = [pwsh_bin, '-NoProfile', '-File', str(self.script_path), '-Action', 'TestHarness']
        try:
            self._proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,  # line-buffered
                encoding='utf-8',
            )
        except FileNotFoundError as exc:
            raise PSHarnessError(f'Could not start pwsh: {exc}') from exc

    @staticmethod
    def _find_pwsh() -> str:
        # Prefer pwsh; fall back to PowerShell (Windows-only).
        for cand in ('pwsh', 'powershell'):
            from shutil import which
            path = which(cand)
            if path:
                return path
        raise PSHarnessError(
            'Neither pwsh nor powershell found on PATH. Install PowerShell 7+ '
            '(https://github.com/PowerShell/PowerShell) to use the test harness.'
        )

    def close(self) -> None:
        if self._proc is None:
            return
        try:
            if self._proc.stdin and not self._proc.stdin.closed:
                self._proc.stdin.close()
            self._proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._proc.kill()
            self._proc.wait()
        finally:
            self._proc = None

    def invoke(self, fn: str, **args: Any) -> Any:
        """Call a PowerShell function and return its parsed JSON result.

        Raises ``PSHarnessError`` if the function call failed inside
        PowerShell (e.g. function not found, parameter validation
        failure, runtime exception).
        """
        if self._proc is None:
            raise PSHarnessError('Session not started; use as context manager or call .start() first.')
        if self._proc.stdin is None or self._proc.stdout is None:
            raise PSHarnessError('Subprocess pipes unavailable.')
        request = {'fn': fn, 'args': args}
        payload = json.dumps(request, separators=(',', ':'), ensure_ascii=False) + '\n'
        try:
            self._proc.stdin.write(payload)
            self._proc.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise PSHarnessError(f'TestHarness stdin closed unexpectedly: {exc}') from exc

        # The TestHarness emits exactly one response object per request on
        # stdout, but a function under test may incidentally write to the host /
        # information stream (e.g. Write-Host logging from the DISM chokepoint),
        # which on some PowerShell hosts renders to stdout. Read until the JSON
        # response line, skipping any non-JSON noise so a stray line cannot
        # desynchronise this long-lived session. The response envelope is a JSON
        # object carrying an "ok" field; empty lines and anything that is not
        # such an envelope are treated as noise.
        noise = []
        resp = None
        while True:
            line = self._proc.stdout.readline()
            if line == '':
                # EOF - the subprocess exited
                stderr = ''
                if self._proc.stderr:
                    try:
                        stderr = self._proc.stderr.read()
                    except Exception:
                        pass
                detail = f'TestHarness exited without a response. stderr: {stderr.strip()[:500]}'
                if noise:
                    detail += f' (skipped non-response output: {noise[-3:]!r})'
                raise PSHarnessError(detail)
            line = line.strip()
            if not line:
                continue
            try:
                candidate = json.loads(line)
            except json.JSONDecodeError:
                noise.append(line[:200])
                continue
            if isinstance(candidate, dict) and 'ok' in candidate:
                resp = candidate
                break
            # Parsed as JSON but not a TestHarness response envelope -> noise.
            noise.append(line[:200])
        if not resp.get('ok'):
            raise PSHarnessError(
                f'PowerShell call {fn!r} failed: {resp.get("error", "<no error message>")}'
            )
        return resp.get('result')
