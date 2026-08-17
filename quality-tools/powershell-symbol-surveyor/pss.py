#!/usr/bin/env python3
"""pss.py - PowerShell Symbol Surveyor.

Surveys a single PowerShell script and emits FACTS about its symbols: functions,
variables, the references between them, and the regions the tool could not
analyse. Given two such surveys, it emits facts about the differences.

The tool exists to make refactoring auditable. It observes AFTER the fact rather
than predicting before it, which is why it never needs to decide whether a
change is safe (SPEC 1.1). It assigns no severity, returns no verdict, and does
not conclude that one symbol is a rename of another. The exit code never encodes
a verdict (SPEC 9).

Design (ADR 0003): single-file, stdlib-only, no cross-tool import. The
string/comment tokenizer below is reuse-by-copy of the canonical normalized-hash
implementation (ADR 0015); conformance is pinned by the shared golden vectors,
not by importing shared code (SPEC 2.5).

Layers (SPEC 2.1):
    Layer 1  extractor    .ps1  ->  symbol model      [this version]
    Layer 2  model        JSON, the stable interface  [this version]
    Layer 3  comparator   model x model -> deltas     [not in this version]

Usage:
    python3 pss.py survey <script.ps1> [--out PATH] [--format text|json] [--axes AXES]
    python3 pss.py slice <model.json> [--scope ID] [--axes AXES] [--out PATH]
    python3 pss.py compare <before.json> <after.json> [--format text|json]
    python3 pss.py --list-facts
    python3 pss.py --self-check
    python3 pss.py --version
"""

import argparse
import bisect
import hashlib
import json
import os
import re
import sys

__version__ = "0.2.0"
MODEL_VERSION = "2"

MIN_PYTHON = (3, 12)

# ---------------------------------------------------------------------------
# Materialisation axes (SPEC 5.6). The vocabulary is closed: --self-check
# verifies these names against the SPEC 5.6 table in both directions. A
# master collection never becomes an axis (SPEC 5.6); an axis only restores
# content already withheld *within* a collection that is always present.
# ---------------------------------------------------------------------------
AXES = {
    "closure-sets": "transitive_callees and transitive_callers on each closure record",
    "local-sites": "one record per function-local variable reference",
    "command-sites": "one record per unresolved command-invocation site, "
                     "alongside the retained per-name aggregates",
}

EXIT_OK = 0
EXIT_ERROR = 2


# ---------------------------------------------------------------------------
# Fact catalogue (SPEC 4). --self-check verifies this table against SPEC.md.
# ---------------------------------------------------------------------------
FACTS = {
    # PSS1xxx - definition inventory
    "PSS1001": "A function is defined.",
    "PSS1002": "A function's parameter signature.",
    "PSS1003": "A function's hash triple.",
    "PSS1004": "A function is defined inside another function's body.",
    "PSS1005": "A function name is defined more than once in the file.",
    # PSS2xxx - reference and binding
    "PSS2001": "A static call edge from one defined function to another.",
    "PSS2002": "A variable declaration site.",
    "PSS2003": "A variable reference resolved to a declaration in the same function.",
    "PSS2004": "A scope-qualified variable reference.",
    "PSS2005": "A reference to a PowerShell automatic variable.",
    "PSS2006": "A script-scope declaration made at script level.",
    "PSS2007": "A variable reference inside an expandable string or here-string.",
    "PSS2008": "A script-scope variable's usage map (writers and readers).",
    "PSS2009": "A command invocation site whose name does not resolve to a function defined in this file.",
    # PSS3xxx - soft reference
    "PSS3001": "A string literal matches a declared function name, not in command position.",
    "PSS3002": "A string literal matches a script-scope variable name.",
    # PSS4xxx - impact closure
    "PSS4001": "The transitive caller closure of a function.",
    "PSS4002": "The transitive callee closure of a function.",
    "PSS4003": "A defined function with no static caller and no top-level invocation.",
    "PSS4004": "A mutual-recursion group (strongly-connected component).",
    # PSS6xxx - presence transition (compare)
    "PSS6001": "A name present in the before model is absent from the after model.",
    "PSS6002": "A name absent from the before model is present in the after model.",
    "PSS6003": "A name is present in both models.",
    # PSS7xxx - attribute change (compare)
    "PSS7001": "Hash-triple classification.",
    "PSS7002": "Parameter signature equality.",
    "PSS7003": "Callee set equality.",
    "PSS7004": "Caller set equality.",
    "PSS7005": "Dependency classification.",
    "PSS7006": "Combined classification.",
    "PSS7007": "A script-scope variable's usage map changed.",
    # PSS8xxx - graph, closure and rename-omission change (compare)
    "PSS8001": "A call edge present in the after model and absent from the before model.",
    "PSS8002": "A call edge present in the before model and absent from the after model.",
    "PSS8003": "A function's transitive closure differs between models.",
    "PSS8004": "A soft reference's resolution state changed.",
    "PSS8005": "Incomplete-rename candidate.",
    "PSS8006": "Producer/consumer desynchronisation candidate.",
    "PSS8007": "Write-site loss.",
    "PSS8008": "A function's PSS4003 presence changed between models (orphaning transition).",
    # PSS9xxx - analysis limitations
    "PSS9001": "A region could not be parsed.",
    "PSS9002": "A call site could not be statically resolved.",
    "PSS9003": "A parent-scope write that cannot be tracked.",
    "PSS9004": "A variable read with no resolvable declaration and no scope qualifier.",
    "PSS9005": "The comparison could not be performed for a named unit.",
    "PSS9006": "Self-diagnostic: an unreachable hash-triple combination was observed.",
    "PSS9007": "A symbol identifier required an ordinal disambiguator.",
}

# ---------------------------------------------------------------------------
# Canonical normalized-hash contract (ADR 0015) - reuse-by-copy of the canon
# implementation, with ONE added policy flag (SPEC 2.5).
#
#   keep_strings=False -> the shared contract, byte-for-byte. Pinned by the
#                         shared golden vectors GV-1..GV-5. Used for hash_full.
#   keep_strings=True  -> string literal CONTENTS are retained; comments are
#                         still stripped. Used for hash_body, which deliberately
#                         diverges from the shared contract (SPEC 10.3) because
#                         stripping strings collapses 12 functions into 3
#                         false-identity groups on the reference target.
#
# The lexical rules are identical in both modes; only the disposition of string
# contents differs. Do NOT "simplify" this into two functions: a duplicated
# normalizer is a normalizer that will drift.
# ---------------------------------------------------------------------------
def _strip_strings_and_comments(text, keep_strings=False):
    out = []
    i, n = 0, len(text)
    in_sq = in_dq = in_lc = in_bc = in_here_sq = in_here_dq = False

    def emit_string_char(ch):
        out.append(ch if keep_strings else ' ')

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if c == '\n':
            out.append('\n')
            if in_lc:
                in_lc = False
            i += 1
            continue
        if in_lc:
            out.append(' '); i += 1; continue
        if in_bc:
            if c == '#' and nxt == '>':
                out.append('  '); in_bc = False; i += 2; continue
            out.append(' '); i += 1; continue
        if in_here_sq:
            if c == "'" and nxt == '@':
                out.append('  ' if not keep_strings else "'@"); in_here_sq = False; i += 2; continue
            emit_string_char(c); i += 1; continue
        if in_here_dq:
            if c == '"' and nxt == '@':
                out.append('  ' if not keep_strings else '"@'); in_here_dq = False; i += 2; continue
            if c == '$':
                out.append('$'); i += 1
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i]); i += 1
                continue
            emit_string_char(c); i += 1; continue
        if in_sq:
            if c == "'":
                if nxt == "'":
                    out.append('  ' if not keep_strings else "''"); i += 2; continue
                in_sq = False; emit_string_char(c); i += 1; continue
            emit_string_char(c); i += 1; continue
        if in_dq:
            if c == '`':
                if i + 1 < n:
                    out.append('  ' if not keep_strings else text[i:i + 2]); i += 2
                else:
                    emit_string_char(c); i += 1
                continue
            if c == '"':
                if nxt == '"':
                    out.append('  ' if not keep_strings else '""'); i += 2; continue
                in_dq = False; emit_string_char(c); i += 1; continue
            if c == '$':
                out.append('$'); i += 1
                if i < n and text[i] == '{':
                    out.append('{'); i += 1
                    while i < n and text[i] != '}':
                        out.append(text[i]); i += 1
                    if i < n:
                        out.append('}'); i += 1
                    continue
                while i < n and (text[i].isalnum() or text[i] in '_:'):
                    out.append(text[i]); i += 1
                continue
            emit_string_char(c); i += 1; continue
        if c == '@' and nxt == "'":
            out.append('  ' if not keep_strings else "@'"); in_here_sq = True; i += 2; continue
        if c == '@' and nxt == '"':
            out.append('  ' if not keep_strings else '@"'); in_here_dq = True; i += 2; continue
        if c == '<' and nxt == '#':
            out.append('  '); in_bc = True; i += 2; continue
        if c == '#':
            out.append(' '); in_lc = True; i += 1; continue
        if c == "'":
            in_sq = True; emit_string_char(c); i += 1; continue
        if c == '"':
            in_dq = True; emit_string_char(c); i += 1; continue
        out.append(c); i += 1
    return ''.join(out)


def canon_norm_hash(text):
    """hash_full contract (SPEC 10.2) - the shared ADR 0015 value, unchanged."""
    clean = _strip_strings_and_comments(text, keep_strings=False)
    normalized = re.sub(r'\s+', ' ', clean).strip()
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]


def body_norm_hash(text):
    """hash_body contract (SPEC 10.3) - string contents retained."""
    clean = _strip_strings_and_comments(text, keep_strings=True)
    normalized = re.sub(r'\s+', ' ', clean).strip()
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()[:16]


def raw_hash(text):
    """hash_raw contract (SPEC 10.4) - verbatim, no normalisation."""
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------
KEYWORDS = frozenset("""
begin break catch class continue data default define do dynamicparam else
elseif end enum exit filter finally for foreach from function hidden if in
inlinescript parallel param process return sequence static switch throw trap
try until using while workflow configuration
""".split())

# Keywords after which the NEXT token still starts a statement, so a command
# name may follow directly: `return Get-Thing`, `else { }`, `throw New-Error`.
# Missing these loses real call edges - on the reference target the `return
# <Command>` form alone accounts for 27 of them.
STATEMENT_KEYWORDS = frozenset("""
begin default do else end finally exit process return throw try
""".split())

# PowerShell automatic variables (SPEC 4.2 PSS2005). The set is enumerated here
# because an unstated set makes the derived count irreproducible, which fails the
# fact test (SPEC 1.3). This is the contract set: 53 names.
#
# `inputobject` is deliberately ABSENT. It is a common parameter name, not an
# automatic variable; including it inflated the reference target's PSS2005 count
# from 2,004 to 2,014 and was the sole cause of that baseline error.
AUTOMATIC_VARIABLES = frozenset("""
_ psitem true false null args input error matches myinvocation pscmdlet
psboundparameters pscommandpath psscriptroot pwd host home profile lastexitcode
pid psversiontable stacktrace this ofs shellid executioncontext consolefilename
nestedpromptlevel psculture psuiculture psdebugcontext psemailserver pshome
psedition islinux ismacos iswindows iscoreclr foreach switch sender eventargs
event eventsubscriber verbosepreference erroractionpreference warningpreference
debugpreference informationpreference progresspreference confirmpreference
whatifpreference outputencoding
""".split())

# A scope-qualified reference is emitted for these; anything else after the
# colon is a PSDrive qualifier (env:, variable:, function:, ...).
_VAR_RE = re.compile(
    r'\$\{[^}]*\}'                                  # ${name} / ${env:Program Files}
    r'|[\$@][A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z_][A-Za-z0-9_]*)?'   # $name / $scope:name / @splat
    r'|\$[\$\?\^]'                                  # $$ $? $^
    r'|\$[0-9]+'                                    # $1 $2 (regex group captures)
)
_WORD_RE = re.compile(r'[A-Za-z_\\/\-][A-Za-z0-9_\\/\-:]*')
_NUM_RE = re.compile(r'[0-9][0-9A-Za-z_.]*')

_COMMENT_OK_BEFORE = frozenset(" \t\r\n(){}[];|,&=+")

# The two-character compound assignment operators, held as one set so the
# tokenizer and the role test cannot enumerate different operators. `??=` is
# three characters and is handled beside this set at both sites.
_ASSIGN_OPS = frozenset(('+=', '-=', '*=', '/=', '%='))

# Tokens after which the next word sits in command position (SPEC 10.6).
# `&&` and `||` are PowerShell 7 pipeline chain operators: the token after one
# starts a new command. They do not occur in the reference target, so no
# baseline moves, but omitting them would silently drop edges in any codebase
# that uses them.
_CMD_POS_OPS = frozenset(("|", ";", "&", "(", "{", "=", "+=", "-=", "*=", "/=",
                          "%=", "??=", "&&", "||"))


class Tok:
    __slots__ = ("kind", "text", "start", "end")

    def __init__(self, kind, text, start, end):
        self.kind = kind
        self.text = text
        self.start = start
        self.end = end

    def __repr__(self):  # pragma: no cover - debugging aid
        return "Tok(%s,%r,%d)" % (self.kind, self.text[:20], self.start)


def _comment_starts_here(text, i):
    if i == 0:
        return True
    return text[i - 1] in _COMMENT_OK_BEFORE


def tokenize(text):
    """Lex PowerShell into a flat token stream with source offsets.

    Kinds: nl ws comment str estr var word num op bt
    'str'  = single-quoted literal or single-quoted here-string (verbatim)
    'estr' = double-quoted literal or double-quoted here-string (expandable)
    """
    toks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if c == '\n':
            toks.append(Tok('nl', c, i, i + 1)); i += 1; continue
        if c in ' \t\r\ufeff':
            j = i
            while j < n and text[j] in ' \t\r\ufeff':
                j += 1
            toks.append(Tok('ws', text[i:j], i, j)); i = j; continue
        if c == '`':
            end = min(i + 2, n)
            toks.append(Tok('bt', text[i:end], i, end)); i = end; continue
        if c == '<' and nxt == '#':
            j = text.find('#>', i + 2)
            j = n if j < 0 else j + 2
            toks.append(Tok('comment', text[i:j], i, j)); i = j; continue
        if c == '#' and _comment_starts_here(text, i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            toks.append(Tok('comment', text[i:j], i, j)); i = j; continue
        if c == '@' and nxt in ("'", '"'):
            q = nxt
            term = "\n'@" if q == "'" else '\n"@'
            j = text.find(term, i + 2)
            end = n if j < 0 else j + 3
            toks.append(Tok('str' if q == "'" else 'estr', text[i:end], i, end))
            i = end; continue
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if text[j + 1:j + 2] == "'":
                        j += 2; continue
                    j += 1; break
                j += 1
            toks.append(Tok('str', text[i:j], i, j)); i = j; continue
        if c == '"':
            j = i + 1
            while j < n:
                ch = text[j]
                if ch == '`':
                    j += 2; continue
                if ch == '"':
                    if text[j + 1:j + 2] == '"':
                        j += 2; continue
                    j += 1; break
                j += 1
            toks.append(Tok('estr', text[i:j], i, j)); i = j; continue
        if c in '$@':
            m = _VAR_RE.match(text, i)
            if m:
                toks.append(Tok('var', m.group(0), i, m.end())); i = m.end(); continue
        # Compound assignment operators are recognised BEFORE the word rule.
        # `-` and `/` are legal word-leading characters (parameter names, paths),
        # so `_WORD_RE` consumed the operator's first character and `-=` / `/=`
        # were emitted as word `-` / word `/` followed by op `=`. `??=` was split
        # by the two-character rule below into op `??` + op `=`. Three of the
        # seven assignment operators the reference-scan enumerates were therefore
        # unreachable, and a compound assignment read as a reference (SPEC 12.2).
        if text.startswith('??=', i):
            toks.append(Tok('op', '??=', i, i + 3)); i += 3; continue
        if text[i:i + 2] in _ASSIGN_OPS:
            toks.append(Tok('op', text[i:i + 2], i, i + 2)); i += 2; continue
        m = _WORD_RE.match(text, i)
        if m:
            toks.append(Tok('word', m.group(0), i, m.end())); i = m.end(); continue
        m = _NUM_RE.match(text, i)
        if m:
            toks.append(Tok('num', m.group(0), i, m.end())); i = m.end(); continue
        for two in ('+=', '-=', '*=', '/=', '%=', '::', '??', '&&', '||'):
            if text.startswith(two, i):
                toks.append(Tok('op', two, i, i + 2)); i += 2; break
        else:
            toks.append(Tok('op', c, i, i + 1)); i += 1
    return toks


def significant(toks):
    """Indices of tokens that participate in structure (ws/comment/bt dropped)."""
    return [k for k, t in enumerate(toks) if t.kind not in ('ws', 'comment', 'bt')]


def iter_command_words(toks, sig):
    """Yield word tokens sitting in command position (SPEC 10.6).

    Command position is: statement start, after `|`, `;`, `&`, `(`, `{`, or an
    assignment operator. Three exclusions keep the population equal to what the
    reference parser calls a command name:

      * PowerShell keywords (`if`, `foreach`, `return`, ...) are not commands;
      * a word followed by an assignment operator is a hashtable key or an
        assignment target (`@{ Name = 'x' }`), not a command;
      * a word starting with `-` is an operator or a parameter name, and a word
        inside brackets sits in an attribute or type-literal context
        (`[Parameter(Mandatory)]`, `[System.IO.Path]`).

    This mirrors the context rules already proven in psa.py's PSA2010.
    """
    cmd_pos = True
    bracket_depth = 0
    paren_stack = []
    prev_kw = False
    for k in range(len(sig)):
        t = toks[sig[k]]
        nxt = toks[sig[k + 1]] if k + 1 < len(sig) else None
        if t.kind == 'op':
            if t.text == '[':
                bracket_depth += 1
            elif t.text == ']':
                bracket_depth = max(0, bracket_depth - 1)
            elif t.text == '(':
                paren_stack.append(prev_kw)
            elif t.text == ')':
                # `param($Msg) _LogLine ...` - the token after a
                # keyword-introduced group starts a statement, so a command may
                # follow it directly.
                opened_after_keyword = paren_stack.pop() if paren_stack else False
                prev_kw = False
                if opened_after_keyword:
                    cmd_pos = True
                    continue
        prev_kw = t.kind == 'word' and t.text.lower() in KEYWORDS
        if t.kind == 'word':
            low = t.text.lower()
            excluded = (
                low in KEYWORDS
                or low.startswith('-')
                or bracket_depth > 0
                or (nxt is not None and nxt.kind == 'op'
                    and nxt.text in ('=', '+=', '-=', '*=', '/=', '%='))
            )
            if cmd_pos and not excluded:
                yield k, t
            if low in STATEMENT_KEYWORDS:
                cmd_pos = True
                continue
        if t.kind == 'nl':
            cmd_pos = True
        elif t.kind == 'op' and (t.text in _CMD_POS_OPS or t.text == '}'):
            cmd_pos = True
        else:
            cmd_pos = False


def subexpression_spans(tok):
    """Absolute (start, end) spans of `$( ... )` regions inside an expandable
    string, innermost content only. A command invoked inside one is a real
    invocation and the reference parser counts it as such."""
    spans = []
    s = tok.text
    base = tok.start
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '`':
            i += 2
            continue
        if c == '$' and i + 1 < n and s[i + 1] == '(':
            depth = 0
            j = i + 1
            while j < n:
                if s[j] == '(':
                    depth += 1
                elif s[j] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            spans.append((base + i + 2, base + j, s[i + 2:j]))
            i = j + 1
            continue
        i += 1
    return spans


# ---------------------------------------------------------------------------
# Variable name analysis
# ---------------------------------------------------------------------------
def parse_var_token(tok_text):
    """Return (qualifier, name, splatted) for a variable token.

    qualifier is one of the scope names, a drive name, or None.
    """
    splatted = tok_text.startswith('@')
    body = tok_text[1:]
    if body.startswith('{') and body.endswith('}'):
        body = body[1:-1]
    qualifier = None
    if ':' in body:
        head, _, tail = body.partition(':')
        if tail:
            qualifier = head.lower()
            body = tail
    return qualifier, body, splatted


def string_value(tok):
    """The literal value of a string token, delimiters and escapes removed."""
    s = tok.text
    if s.startswith("@'") or s.startswith('@"'):
        inner = s[2:]
        if inner.startswith('\r\n'):
            inner = inner[2:]
        elif inner.startswith('\n'):
            inner = inner[1:]
        for term in ("\n'@", '\n"@'):
            if inner.endswith(term):
                inner = inner[:-3]
                break
        return inner
    if s.startswith("'"):
        inner = s[1:-1] if s.endswith("'") and len(s) >= 2 else s[1:]
        return inner.replace("''", "'")
    if s.startswith('"'):
        inner = s[1:-1] if s.endswith('"') and len(s) >= 2 else s[1:]
        return inner.replace('""', '"')
    return s


def expandable_var_sites(tok):
    """Variable references inside an expandable string (SPEC 12.4).

    Returns [(absolute_offset, var_text)]. Sub-expressions `$( ... )` are
    recursed into, because the reference inside one is a real reference.
    """
    sites = []
    s = tok.text
    base = tok.start
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '`':
            i += 2
            continue
        if c == '$' and i + 1 < n and s[i + 1] == '(':
            depth = 0
            j = i + 1
            while j < n:
                if s[j] == '(':
                    depth += 1
                elif s[j] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            inner = s[i + 2:j]
            for sub in tokenize(inner):
                if sub.kind == 'var':
                    sites.append((base + i + 2 + sub.start, sub.text))
                elif sub.kind == 'estr':
                    sub.start += base + i + 2
                    sub.end += base + i + 2
                    sites.extend(expandable_var_sites(sub))
            i = j + 1
            continue
        if c == '$':
            m = _VAR_RE.match(s, i)
            if m:
                sites.append((base + i, m.group(0)))
                i = m.end()
                continue
        i += 1
    return sites


# ---------------------------------------------------------------------------
# Structure pass
# ---------------------------------------------------------------------------
class FunctionDef:
    __slots__ = ("name", "name_end", "start", "end", "body_start", "body_end",
                 "param_span", "depth", "parent", "ordinal", "sig_span")

    def __init__(self, name, name_end, start, end, body_start, body_end,
                 param_span, sig_span):
        self.name = name
        self.name_end = name_end
        self.start = start
        self.end = end
        self.body_start = body_start
        self.body_end = body_end
        self.param_span = param_span
        self.sig_span = sig_span
        self.depth = 0
        self.parent = None
        self.ordinal = None


def _match_brace(toks, sig, pos):
    """Given index into sig of an opening '{', return index of its match."""
    depth = 0
    for k in range(pos, len(sig)):
        t = toks[sig[k]]
        if t.kind == 'op' and t.text == '{':
            depth += 1
        elif t.kind == 'op' and t.text == '}':
            depth -= 1
            if depth == 0:
                return k
    return None


def _match_paren(toks, sig, pos):
    depth = 0
    for k in range(pos, len(sig)):
        t = toks[sig[k]]
        if t.kind == 'op' and t.text == '(':
            depth += 1
        elif t.kind == 'op' and t.text == ')':
            depth -= 1
            if depth == 0:
                return k
    return None


def find_functions(toks, sig):
    """Locate function/filter definitions (SPEC 10.1).

    A definition is a `function`/`filter` keyword in command position, followed
    by a name, an optional parenthesised parameter list, then an opening brace.
    Regular expressions cannot do this: on the reference target a naive pattern
    counts prose inside comments as definitions (SPEC Appendix D.2). Comments
    are already separate tokens here, so they cannot contribute.
    """
    funcs = []
    cmd_pos = True
    k = 0
    while k < len(sig):
        t = toks[sig[k]]
        if t.kind == 'word' and t.text.lower() in ('function', 'filter') and cmd_pos:
            k2 = k + 1
            if k2 < len(sig) and toks[sig[k2]].kind in ('word', 'str', 'estr'):
                name_tok = toks[sig[k2]]
                name = name_tok.text if name_tok.kind == 'word' else string_value(name_tok)
                param_span = None
                k3 = k2 + 1
                if k3 < len(sig) and toks[sig[k3]].kind == 'op' and toks[sig[k3]].text == '(':
                    close = _match_paren(toks, sig, k3)
                    if close is None:
                        k += 1
                        continue
                    param_span = (k3 + 1, close)
                    k3 = close + 1
                if k3 < len(sig) and toks[sig[k3]].kind == 'op' and toks[sig[k3]].text == '{':
                    close = _match_brace(toks, sig, k3)
                    if close is None:
                        k += 1
                        continue
                    funcs.append(FunctionDef(
                        name=name,
                        name_end=name_tok.end,
                        start=t.start,
                        end=toks[sig[close]].end,
                        body_start=toks[sig[k3]].start,
                        body_end=toks[sig[close]].end,
                        param_span=param_span,
                        sig_span=(k3, close),
                    ))
                    cmd_pos = True
                    k = k3 + 1
                    continue
        if t.kind == 'nl':
            cmd_pos = True
        elif t.kind == 'op' and t.text in _CMD_POS_OPS:
            cmd_pos = True
        elif t.kind == 'op' and t.text == '}':
            cmd_pos = True
        else:
            cmd_pos = False
        k += 1

    funcs.sort(key=lambda f: (f.start, -f.end))
    for a in funcs:
        enclosing = None
        for b in funcs:
            if b is a:
                continue
            if b.start <= a.start and a.end <= b.end:
                if enclosing is None or b.start > enclosing.start:
                    enclosing = b
        if enclosing is not None:
            a.parent = enclosing
            a.depth = 1
    changed = True
    while changed:
        changed = False
        for f in funcs:
            if f.parent is not None and f.depth != f.parent.depth + 1:
                f.depth = f.parent.depth + 1
                changed = True

    seen = {}
    dupes = set()
    for f in funcs:
        key = f.name.lower()
        seen.setdefault(key, []).append(f)
    for key, group in seen.items():
        if len(group) > 1:
            dupes.add(key)
            for idx, f in enumerate(group, 1):
                f.ordinal = idx
    return funcs, dupes


def function_id(f):
    parts = [f.name]
    p = f.parent
    while p is not None:
        parts.append(p.name)
        p = p.parent
    ident = "function/" + "/".join(reversed(parts))
    if f.ordinal is not None:
        ident += "#%d" % f.ordinal
    return ident


# ---------------------------------------------------------------------------
# Parameter extraction (SPEC 4.1 PSS1002, 10.1)
# ---------------------------------------------------------------------------
def _split_top_level(toks, sig, lo, hi):
    """Split a token span on top-level commas."""
    parts = []
    depth = 0
    cur = []
    for k in range(lo, hi):
        t = toks[sig[k]]
        if t.kind == 'op':
            if t.text in '([{':
                depth += 1
            elif t.text in ')]}':
                depth -= 1
            elif t.text == ',' and depth == 0:
                parts.append(cur); cur = []; continue
        cur.append(k)
    if cur:
        parts.append(cur)
    return [p for p in parts if p]


def _parse_param_entry(toks, sig, idxs, position):
    # The parameter variable is the one at bracket/paren depth 0. Taking the
    # first var token instead picks up `$true` from
    # `[Parameter(Mandatory=$true)] [string]$Path`, which then registers the
    # parameter under the wrong name and leaves every read of $Path looking
    # unresolvable.
    var_pos = None
    depth = 0
    for k in idxs:
        t = toks[sig[k]]
        if t.kind == 'op':
            if t.text in '([{':
                depth += 1
            elif t.text in ')]}':
                depth -= 1
            continue
        if t.kind == 'var' and depth == 0:
            var_pos = k
            break
    if var_pos is None:
        return None
    qualifier, name, _ = parse_var_token(toks[sig[var_pos]].text)
    # The type constraint is the bracket group immediately before the variable;
    # anything earlier is an attribute.
    declared_type = None
    pre = [k for k in idxs if k < var_pos]
    if pre and toks[sig[pre[-1]]].kind == 'op' and toks[sig[pre[-1]]].text == ']':
        depth = 0
        start = None
        for k in reversed(pre):
            t = toks[sig[k]]
            if t.kind == 'op' and t.text == ']':
                depth += 1
            elif t.kind == 'op' and t.text == '[':
                depth -= 1
                if depth == 0:
                    start = k
                    break
        if start is not None:
            declared_type = "".join(toks[sig[k]].text for k in range(start + 1, pre[-1]))
    attr_text = "".join(toks[sig[k]].text for k in pre).lower()
    mandatory = bool(re.search(r'mandatory\s*=\s*\$true', attr_text)) or bool(
        re.search(r'mandatory\s*[,)\]]', attr_text))
    return {
        "name": name,
        "type": declared_type,
        "mandatory": mandatory,
        "position": position,
        "qualifier": qualifier,
    }


def extract_parameters(toks, sig, func):
    """Both `function f($a)` and a `param(...)` block in the body (SPEC 10.1)."""
    entries = []
    if func.param_span is not None:
        lo, hi = func.param_span
        for pos, part in enumerate(_split_top_level(toks, sig, lo, hi)):
            e = _parse_param_entry(toks, sig, part, pos)
            if e:
                entries.append(e)
        return entries
    body_lo, body_hi = func.sig_span
    depth = 0
    for k in range(body_lo, body_hi):
        t = toks[sig[k]]
        if t.kind == 'op' and t.text == '{':
            depth += 1
            continue
        if t.kind == 'op' and t.text == '}':
            depth -= 1
            continue
        if depth == 1 and t.kind == 'word' and t.text.lower() == 'param':
            k2 = k + 1
            if k2 < body_hi and toks[sig[k2]].kind == 'op' and toks[sig[k2]].text == '(':
                close = _match_paren(toks, sig, k2)
                if close is None:
                    break
                for pos, part in enumerate(_split_top_level(toks, sig, k2 + 1, close)):
                    e = _parse_param_entry(toks, sig, part, pos)
                    if e:
                        entries.append(e)
                break
    return entries


# ---------------------------------------------------------------------------
# Survey
# ---------------------------------------------------------------------------
class LineIndex:
    def __init__(self, text):
        self.starts = [0]
        for m in re.finditer('\n', text):
            self.starts.append(m.end())

    def line_of(self, offset):
        return bisect.bisect_right(self.starts, offset)


def bracket_depths(toks, sig):
    """Bracket nesting depth at each significant token index."""
    depths = []
    d = 0
    for k in range(len(sig)):
        t = toks[sig[k]]
        if t.kind == 'op' and t.text == '[':
            d += 1
            depths.append(d)
            continue
        if t.kind == 'op' and t.text == ']':
            depths.append(d)
            d = max(0, d - 1)
            continue
        depths.append(d)
    return depths


COST_KEY = "cost"
COST_FORMAT = "json-compact"


def compact_bytes(obj):
    """The serialisation every cost figure is measured in (SPEC 3.1).

    A size figure that names neither its serialisation nor its subject is not a
    fact (SPEC 1.3), so the convention is fixed here and reported as ``format``.
    """
    return len(json.dumps(obj, separators=(',', ':'),
                          ensure_ascii=False).encode('utf-8'))


def cost_block(model, axis_increments):
    """Price a model per collection, with the remainder named rather than lost.

    The per-collection figure is the byte length of that collection's compact
    array **alone** - no key name, colon or separator - and everything else,
    the top-level scalars and objects and all the structural punctuation, is
    reported as ``envelope``. The two therefore sum to the whole exactly:

        sum(by_collection[*].bytes) + envelope.bytes == model_bytes

    and a consumer can check that from the model file without this tool.
    ``envelope`` is emitted even when it would be zero, so the reconciliation is
    testable rather than inferable - a report that governs itself by
    reproducibility and cannot reconcile its own arithmetic fails its own rule.

    ``model`` here never carries the block itself, which is what makes the
    measurement well-defined rather than self-referential, and what keeps the
    block from growing with the thing it describes: its size is set by the
    number of collections and the number of axes, both closed vocabularies.

    The report carries no threshold and no recommendation. How large a thing is
    is a fact; whether that is too large is the caller's judgement (SPEC 1.2).
    """
    by_collection = []
    total = compact_bytes(model)
    accounted = 0
    for key in sorted(k for k, v in model.items() if isinstance(v, list)):
        size = compact_bytes(model[key])
        accounted += size
        by_collection.append({"collection": key,
                              "records": len(model[key]),
                              "bytes": size})
    return {
        "format": COST_FORMAT,
        "measured": "the model excluding this block",
        "source_sha256": model["source"]["sha256"],
        "model_bytes": total,
        "by_collection": by_collection,
        "envelope": {"bytes": total - accounted},
        "axis_increment": [{"axis": axis, "bytes": axis_increments[axis]}
                           for axis in sorted(axis_increments)],
    }


class Survey:
    def __init__(self, path, text, axes=frozenset()):
        self.path = path
        self.text = text
        self.axes = frozenset(axes)
        self.lines = LineIndex(text)
        self.toks = tokenize(text)
        self.sig = significant(self.toks)
        self.funcs, self.dupes = find_functions(self.toks, self.sig)
        self.func_by_lname = {}
        for f in self.funcs:
            self.func_by_lname.setdefault(f.name.lower(), []).append(f)
        self.func_ids = {id(f): function_id(f) for f in self.funcs}
        self.limitations = []
        self.edges = {}
        self.params_by_func = {}

        # Variable analysis is deliberately TWO-PASS. Whether an unqualified
        # reference binds to the script scope depends on whether its enclosing
        # function declares the name anywhere in its body - which is not known
        # until the whole function has been scanned. Classifying on first sight
        # would put every accidental name collision (`$result`, `$line`, `$cmd`)
        # into the script-scope usage map and destroy the population that
        # PSS8005-PSS8007 depend on.
        self.var_sites = []
        self.local_decls = {}
        self.script_decl_names = {}
        self.script_qualified_names = {}

        self.script_records = []
        self.interp_records = []
        self.local_aggregates = {}
        self.detail_records = []
        self.soft_refs = []
        self.unresolved_named_commands = []
        self.usage = {}
        self.counters = {
            "commands_named": 0,
            "commands_dynamic": 0,
            "unresolved_named_command_sites": 0,
            "variable_refs": 0,
            "string_literals_quoted": 0,
            "string_literals_bareword": 0,
            "expandable_strings": 0,
            "interpolation_refs": 0,
            "assignments": 0,
        }

    # -- ownership ---------------------------------------------------------
    def line_of(self, offset):
        return self.lines.line_of(offset)

    def _owner_cache_build(self):
        self._intervals = sorted(
            ((f.start, f.end, f) for f in self.funcs), key=lambda x: (x[0], -x[1]))
        self._ivstarts = [iv[0] for iv in self._intervals]

    def owner_fast(self, offset):
        """Innermost enclosing function. A nested function owns its own
        references and does NOT also attribute them to the enclosing function
        (SPEC 10.8); double attribution is what made the reference target's
        class totals overshoot by 11."""
        k = bisect.bisect_right(self._ivstarts, offset) - 1
        best = None
        while k >= 0:
            s, e, f = self._intervals[k]
            if offset < e and (best is None or s > best.start):
                best = f
                break
            k -= 1
        if best is None:
            return None
        changed = True
        while changed:
            changed = False
            for s, e, f in self._intervals:
                if f.parent is best and s <= offset < e:
                    best = f
                    changed = True
                    break
        return best

    def _owner_id_fast(self, offset):
        f = self.owner_fast(offset)
        return self.func_ids[id(f)] if f is not None else "<script>"

    # -- passes ------------------------------------------------------------
    def run(self):
        self._owner_cache_build()
        self._precompute_parameters()
        self._scan()
        self._classify_variables()
        self._build_usage_map()
        self._scan_soft_references()
        self._compute_closures()
        return self

    def _decl_add(self, owner, name):
        low = name.lower()
        if low in AUTOMATIC_VARIABLES:
            # Automatic variables are never declarations. `$null = Get-Thing` is
            # the output-discard idiom and `$ProgressPreference = 'X'` writes a
            # preference variable; treating either as a declaration misclassifies
            # 254 references on the reference target (SPEC 4.2, check order).
            return
        if owner == "<script>":
            self.script_decl_names.setdefault(low, name)
        else:
            self.local_decls.setdefault(owner, set()).add(low)

    def _precompute_parameters(self):
        toks, sig = self.toks, self.sig
        for f in self.funcs:
            entries = extract_parameters(toks, sig, f)
            self.params_by_func[id(f)] = entries
            fid = self.func_ids[id(f)]
            for e in entries:
                self._decl_add(fid, e["name"])
        # EVERY param() block declares names in its owner, not just the one that
        # forms a function's signature. A script-level param() declares
        # script-scope variables, and a script block's param() - `$add = {
        # param($Level, $Kind, $Message) ... }` - declares names that are
        # perfectly resolvable from the enclosing function. Missing the latter
        # reported 19 spurious PSS9004 unresolved reads on the reference target.
        for k in range(len(sig)):
            t = toks[sig[k]]
            if t.kind != 'word' or t.text.lower() != 'param':
                continue
            if k + 1 >= len(sig) or toks[sig[k + 1]].kind != 'op' \
                    or toks[sig[k + 1]].text != '(':
                continue
            close = _match_paren(toks, sig, k + 1)
            if close is None:
                continue
            owner = self._owner_id_fast(t.start)
            for pos, part in enumerate(_split_top_level(toks, sig, k + 2, close)):
                e = _parse_param_entry(toks, sig, part, pos)
                if e:
                    self._decl_add(owner, e["name"])

    def _scan(self):
        toks, sig = self.toks, self.sig
        self._scan_command_stream(toks, sig)

        cmd_pos = True
        for k in range(len(sig)):
            t = toks[sig[k]]
            nxt = toks[sig[k + 1]] if k + 1 < len(sig) else None

            if t.kind == 'estr':
                self.counters["expandable_strings"] += 1
                for off, vtext in expandable_var_sites(t):
                    self._note_variable(off, vtext, in_string=True, role="read")
                for lo, hi, inner in subexpression_spans(t):
                    sub = tokenize(inner)
                    for tk in sub:
                        tk.start += lo
                        tk.end += lo
                    self._scan_command_stream(sub, significant(sub))

            if t.kind == 'var':
                role = "read"
                prv = toks[sig[k - 1]] if k > 0 else None
                # A variable in member-name position (`$obj.$name`, `$t::$name`)
                # is being READ to supply the name; the assignment that follows
                # targets the member, not the variable. Without this look-behind
                # the look-ahead below sees `=` and declares the member name -
                # the corruption SPEC 12.2 excludes static member left-hand
                # sides to avoid, arriving through the dynamic form instead.
                member_name = (prv is not None and prv.kind == 'op'
                               and prv.text in ('.', '::'))
                if nxt is not None and nxt.kind == 'op' and not member_name:
                    if nxt.text == '=' or nxt.text == '??=' or nxt.text in _ASSIGN_OPS:
                        role = "write"
                    elif nxt.text in ('.', '[', '::'):
                        # A member or index left-hand side REFERENCES the
                        # variable; it never declares anything (SPEC 12.2).
                        role = "read"
                self._note_variable(t.start, t.text, in_string=False, role=role)
                if role == "write":
                    self.counters["assignments"] += 1

            if t.kind == 'word':
                low = t.text.lower()
                if cmd_pos and low == 'foreach':
                    self._record_foreach(k)
                if low in ('set-variable', 'new-variable'):
                    self._record_set_variable(k)

            if t.kind == 'op' and t.text in ('&', '.') and nxt is not None and cmd_pos:
                if nxt.kind == 'var' or (nxt.kind == 'op' and nxt.text == '('):
                    self.counters["commands_dynamic"] += 1
                    self.limitations.append({
                        "code": "PSS9002",
                        "owner": self._owner_id_fast(t.start),
                        "line": self.line_of(t.start),
                        "detail": "invocation through '%s' with a non-literal target" % t.text,
                    })

            if t.kind == 'nl':
                cmd_pos = True
            elif t.kind == 'op' and (t.text in _CMD_POS_OPS or t.text == '}'):
                cmd_pos = True
            else:
                cmd_pos = False

    def _scan_command_stream(self, toks, sig):
        for k, t in iter_command_words(toks, sig):
            self.counters["commands_named"] += 1
            targets = self.func_by_lname.get(t.text.lower())
            if not targets:
                # SPEC 15.4 F4 / P25: counted here, once per model, in
                # counters - never repeated on each PSS2009 record (SPEC
                # 4.4). Most of these are cmdlets and external executables
                # (SPEC 15.4 F2 / P23): the collection below is not a list of
                # errors, and classifying an entry is the caller's work, not
                # this tool's - pss.py has no structural way to tell a
                # deleted local function from a cmdlet name (SPEC 1.3
                # forbids guessing that from naming convention).
                self.counters["unresolved_named_command_sites"] += 1
                self.unresolved_named_commands.append({
                    "code": "PSS2009", "name": t.text,
                    "owner": self._owner_id_fast(t.start),
                    "line": self.line_of(t.start), "offset": t.start,
                })
                continue
            # The edge source may be <script>: a function called only from top
            # level is not an orphan, and excluding script-level edges makes 12
            # such functions falsely report PSS4003 (SPEC 4.2, revised).
            src = self._owner_id_fast(t.start)
            dst = self.func_ids[id(targets[0])]
            rec = self.edges.get((src, dst))
            if rec is None:
                self.edges[(src, dst)] = {"from": src, "to": dst,
                                          "line": self.line_of(t.start), "sites": 1}
            else:
                rec["sites"] += 1

    def _record_foreach(self, k):
        toks, sig = self.toks, self.sig
        if k + 2 < len(sig) and toks[sig[k + 1]].kind == 'op' \
                and toks[sig[k + 1]].text == '(' and toks[sig[k + 2]].kind == 'var':
            v = toks[sig[k + 2]]
            _, name, _ = parse_var_token(v.text)
            self._decl_add(self._owner_id_fast(v.start), name)

    def _record_set_variable(self, k):
        toks, sig = self.toks, self.sig
        for j in range(k + 1, min(k + 12, len(sig))):
            t = toks[sig[j]]
            if t.kind == 'word' and t.text.lower() == '-name':
                if j + 1 < len(sig) and toks[sig[j + 1]].kind in ('str', 'estr', 'word'):
                    nm = toks[sig[j + 1]]
                    value = string_value(nm) if nm.kind in ('str', 'estr') else nm.text
                    self._decl_add(self._owner_id_fast(nm.start), value)
                return
            if t.kind == 'word' and t.text.lower() == '-scope':
                self.limitations.append({
                    "code": "PSS9003",
                    "owner": self._owner_id_fast(t.start),
                    "line": self.line_of(t.start),
                    "detail": "parent-scope write via -Scope cannot be tracked statically",
                })
            if t.kind == 'nl':
                return

    def _note_variable(self, offset, vtext, in_string, role):
        qualifier, name, splatted = parse_var_token(vtext)
        self.counters["variable_refs"] += 1
        if in_string:
            self.counters["interpolation_refs"] += 1
        owner = self._owner_id_fast(offset)
        if qualifier is None and role == "write":
            self._decl_add(owner, name)
        if qualifier == 'script':
            self.script_qualified_names.setdefault(name.lower(), name)
        self.var_sites.append({
            "offset": offset, "name": name, "qualifier": qualifier,
            "owner": owner, "role": role, "in_string": in_string,
            "splatted": splatted,
        })

    def _classify_variables(self):
        """Assign every reference to exactly one class (SPEC 12.6).

        Check order is normative: qualifier, then automatic, then declaration.
        """
        for s in self.var_sites:
            name, low = s["name"], s["name"].lower()
            owner, role, offset = s["owner"], s["role"], s["offset"]
            line = self.line_of(offset)
            base = {
                "record": "reference", "name": name, "owner": owner,
                "line": line, "offset": offset, "role": role,
                "in_expandable_string": s["in_string"],
            }
            if s["in_string"]:
                # PSS2007 is an explicit exception to the SPEC 5.3 tiering rule:
                # these are the principal path by which a text-substitution
                # rename fails silently, and there are only 118 of them.
                rec = dict(base)
                rec["code"] = "PSS2007"
                rec["id"] = "variable:%s/%s" % (s["qualifier"] or "unqualified", name)
                rec["qualifier"] = s["qualifier"]
                self.interp_records.append(rec)

            if s["qualifier"] is not None:
                scope = s["qualifier"]
                rec = dict(base)
                rec["code"] = "PSS2004"
                rec["qualifier"] = scope
                rec["id"] = "variable:%s/%s" % (scope, name)
                self.script_records.append(rec)
                if scope == 'script':
                    self._usage_add(low, name, owner, role)
                continue

            if low in AUTOMATIC_VARIABLES:
                self._agg(owner)["automatic_refs"] += 1
                if "local-sites" in self.axes:
                    rec = dict(base)
                    rec["code"] = "PSS2005"
                    rec["id"] = "variable:automatic/%s" % low
                    self.detail_records.append(rec)
                continue

            if owner == "<script>":
                rec = dict(base)
                rec["code"] = "PSS2006" if role == "write" else "PSS2004"
                rec["qualifier"] = "script"
                rec["id"] = "variable:script/" + name
                self.script_records.append(rec)
                self.script_decl_names.setdefault(low, name)
                if low in self.usage or low in self.script_qualified_names:
                    self._usage_add(low, name, owner, role)
                continue

            if low in self.local_decls.get(owner, ()):
                agg = self._agg(owner)
                agg["local_refs"] += 1
                if role == "write":
                    agg["local_declared"] += 1
                if "local-sites" in self.axes:
                    rec = dict(base)
                    # PSS2002 (declaration) vs PSS2003 (reference to one) is the
                    # same role split already used for PSS2006/PSS2004 at
                    # <script> scope above. Coverage note (SPEC 4.2, 12.2): this
                    # captures the assignment-derived declaration sites (the
                    # `role == "write"` var-token case). Declarations that never
                    # produce a var-token write here - a `param()` entry, a
                    # `foreach` loop variable, a `Set-Variable`/`New-Variable`
                    # `-Name` - are still counted in `local_declared` above via
                    # `_decl_add`, but `_decl_add`'s callers do not keep a site
                    # (line/offset) to tag, so those declarations do not yet get
                    # a PSS2002 record here. Known gap, tracked in SPEC, not
                    # silently absorbed.
                    rec["code"] = "PSS2002" if role == "write" else "PSS2003"
                    rec["id"] = "variable:local/%s#%s" % (owner.split('/')[-1], name)
                    self.detail_records.append(rec)
                continue

            # No qualifier, not automatic, no local declaration: the read cannot
            # be resolved from this function alone.
            self._agg(owner)["unresolved_refs"] += 1
            self.limitations.append({
                "code": "PSS9004", "owner": owner, "line": line,
                "detail": "read of '$%s' with no local declaration and no scope "
                          "qualifier" % name,
            })
            if low in self.script_decl_names:
                # Declared at script level and not shadowed here, so the binding
                # really does reach the script scope. This - and ONLY this - is
                # what admits an unqualified name to the usage map.
                self._usage_add(low, self.script_decl_names[low], owner, role)

    def _agg(self, owner):
        a = self.local_aggregates.get(owner)
        if a is None:
            a = {"record": "aggregate", "owner": owner, "local_declared": 0,
                 "local_refs": 0, "automatic_refs": 0, "unresolved_refs": 0}
            self.local_aggregates[owner] = a
        return a

    def _usage_add(self, low, name, owner, role):
        u = self.usage.get(low)
        if u is None:
            u = {"record": "usage_map", "code": "PSS2008",
                 "id": "variable:script/" + name, "name": name,
                 "writers": set(), "readers": set()}
            self.usage[low] = u
        if role == "write":
            u["writers"].add(owner)
        u["readers"].add(owner)

    def _build_usage_map(self):
        # A script-qualified name always belongs, even if every site is a read.
        for low, name in self.script_qualified_names.items():
            if low not in self.usage:
                self.usage[low] = {"record": "usage_map", "code": "PSS2008",
                                   "id": "variable:script/" + name, "name": name,
                                   "writers": set(), "readers": set()}
        for u in self.usage.values():
            u["writer_count"] = len(u["writers"])
            u["reader_count"] = len(u["readers"])

    def _scan_soft_references(self):
        """PSS3001 / PSS3002 over the full string-constant population.

        Barewords count. In the PowerShell AST a bareword argument and a
        hashtable key are both string constants, and on the reference target 131
        of the 146 PSS3002 hits are barewords - dropping them would hide exactly
        the output-field-name cases a rename has to consider. Each record
        carries literal_kind so the caller can filter (SPEC 4.3).
        """
        toks, sig = self.toks, self.sig
        depths = bracket_depths(toks, sig)
        cmd_words = set(k for k, _t in iter_command_words(toks, sig))

        def is_member_name(k):
            """A literal in member position names a .NET member, not a symbol.

            The reference parser represents `$proc.ExitCode` with a string
            constant for `ExitCode`, so a naive population treats it as a soft
            reference to `$script:ExitCode`. Renaming that variable requires no
            edit to `$proc.ExitCode`. 9,614 of the reference target's 27,626
            string constants are member names, and 42 of the 146 raw PSS3002
            hits - 29 per cent - are this false positive. PSS3001 is unaffected:
            function names are not used as property names (measured: 0).
            """
            if k == 0:
                return False
            prev = toks[sig[k - 1]]
            return prev.kind == 'op' and prev.text in ('.', '::')
        # The name token of a definition is part of the definition syntax, not a
        # string constant. Counting it matched all 480 definitions against
        # themselves and inflated PSS3001 from 49 to 529.
        def_name_ends = set(f.name_end for f in self.funcs)
        fnames = set(self.func_by_lname)
        snames = self.script_qualified_names
        for k in range(len(sig)):
            t = toks[sig[k]]
            kind = None
            if t.kind == 'str':
                kind = "quoted"
                value = string_value(t)
            elif t.kind == 'estr':
                if expandable_var_sites(t) or subexpression_spans(t):
                    continue  # expandable string, not a string constant
                kind = "quoted"
                value = string_value(t)
            elif t.kind == 'word':
                low0 = t.text.lower()
                # A bareword command NAME is still a string constant, so it
                # stays in the population; PSS3001 excludes it separately via
                # the command-position test below.
                if low0.startswith('-') or low0 in KEYWORDS \
                        or depths[k] > 0 or t.end in def_name_ends:
                    continue
                kind = "bareword"
                value = t.text
            if kind is None or is_member_name(k):
                continue
            if kind == "quoted":
                self.counters["string_literals_quoted"] += 1
            else:
                self.counters["string_literals_bareword"] += 1
            if not value.strip():
                continue
            low = value.lower()
            owner = self._owner_id_fast(t.start)
            if low in fnames and k not in cmd_words:
                self.soft_refs.append({
                    "code": "PSS3001", "literal": value, "literal_kind": kind,
                    "matches": self.func_ids[id(self.func_by_lname[low][0])],
                    "owner": owner, "line": self.line_of(t.start), "offset": t.start,
                })
            if low in snames:
                self.soft_refs.append({
                    "code": "PSS3002", "literal": value, "literal_kind": kind,
                    "matches": "variable:script/" + snames[low],
                    "owner": owner, "line": self.line_of(t.start), "offset": t.start,
                })

    def _compute_closures(self):
        adj = {}
        radj = {}
        for (src, dst) in self.edges:
            adj.setdefault(src, set()).add(dst)
            radj.setdefault(dst, set()).add(src)
        self.adj = adj
        self.radj = radj

        def closure(start, graph):
            seen = set()
            stack = [start]
            while stack:
                cur = stack.pop()
                for nxt in graph.get(cur, ()):
                    if nxt not in seen:
                        seen.add(nxt)
                        stack.append(nxt)
            return seen

        self.closures = []
        for f in self.funcs:
            fid = self.func_ids[id(f)]
            callees = sorted(closure(fid, adj))
            callers = sorted(closure(fid, radj))
            # The edge list is the master and the closures are a derived view
            # (SPEC 11.1). Materialising the direct sets here republished all
            # 1,281 edges a second time, and materialising both transitive sets
            # for all 480 functions cost 601 KB - the largest collection in the
            # model - to answer a question a consumer asks about a handful of
            # functions at a time. Counts are actionable on their own ("97
            # functions are downstream of this one"); the sets themselves are
            # available under the closure-sets axis (SPEC 5.6). `no_static_caller`
            # is omitted because the PSS4003 records already carry it.
            rec = {
                "record": "closure", "id": fid,
                "facts": ["PSS4001", "PSS4002"],
                "transitive_callee_count": len(callees),
                "transitive_caller_count": len(callers),
            }
            if "closure-sets" in self.axes:
                rec["transitive_callees"] = callees
                rec["transitive_callers"] = callers
            self.closures.append(rec)
        self.sccs = _tarjan_scc(adj, [self.func_ids[id(f)] for f in self.funcs])

    @staticmethod
    def _emit(records):
        """Final projection: drop the sort key and any absent-valued field.

        `offset` exists to make ordering total and reproducible; it is not a
        coordinate any consumer uses, and `line` is. A key whose value is null
        or false carries no information that its absence does not, and on the
        reference target those keys alone cost 164 KB.
        """
        out = []
        for r in records:
            out.append({k: v for k, v in r.items()
                        if k != "offset" and v is not None and v is not False})
        return out

    def _unresolved_command_records(self):
        """SPEC 15.4 F2 / P23. A per-name aggregate is always present; the
        `command-sites` axis additionally restores one record per site. Same
        collection, two record shapes - the local_variables idiom (SPEC 5.3
        aggregate / SPEC 5.6 axis-restored site), applied here because the
        measured cost of the site-level form (22.3% of the reference
        target's base model) matches the order of magnitude that motivated
        that idiom the first time, not because this is a new mechanism.

        `owners` groups by the SAME field `--scope` matches elsewhere
        (`owner`, SPEC 5.7): a caller slicing to one function retains an
        aggregate row exactly when that function is among its unresolved
        call sites, without needing the axis to know that much.
        """
        by_name = {}
        for r in self.unresolved_named_commands:
            key = r["name"].lower()
            agg = by_name.get(key)
            if agg is None:
                agg = {"name": r["name"], "sites": 0, "owners": set()}
                by_name[key] = agg
            agg["sites"] += 1
            agg["owners"].add(r["owner"])
        records = [
            {"record": "aggregate", "code": "PSS2009", "name": a["name"],
             "sites": a["sites"], "owners": sorted(a["owners"])}
            for a in sorted(by_name.values(), key=lambda a: a["name"])
        ]
        if "command-sites" in self.axes:
            records += [
                {"record": "site", "code": "PSS2009", "name": r["name"],
                 "owner": r["owner"], "line": r["line"], "offset": r["offset"]}
                for r in sorted(self.unresolved_named_commands,
                                key=lambda r: (r["name"], r["offset"]))
            ]
        return records

    # -- model -------------------------------------------------------------
    def model(self, with_cost=True):
        """Emit the model. ``with_cost`` is False only for the internal runs the
        cost block itself needs, which is what keeps the measurement
        well-defined rather than self-referential (SPEC 3.1)."""
        symbols = []
        for f in self.funcs:
            fid = self.func_ids[id(f)]
            extent = self.text[f.start:f.end]
            # hash_body covers the extent MINUS the keyword and the name, not
            # "the brace-delimited block": the two definition forms
            # `function f { param($a) }` and `function f($a) { }` must hash the
            # parameter names alike, or PSS7001 would depend on syntax choice
            # rather than on content (SPEC 10.3, revised).
            body = self.text[f.name_end:f.end]
            facts = ["PSS1001", "PSS1002", "PSS1003"]
            if f.parent is not None:
                facts.append("PSS1004")
            if f.ordinal is not None:
                facts.extend(["PSS1005", "PSS9007"])
                self.limitations.append({
                    "code": "PSS9007", "owner": fid,
                    "line": self.line_of(f.start),
                    "detail": "identifier carries a position-dependent ordinal; "
                              "not a durable key",
                })
            symbols.append({
                "id": fid,
                "name": f.name,
                "kind": "function",
                "start_line": self.line_of(f.start),
                "end_line": self.line_of(f.end),
                "offset": f.start,
                "depth": f.depth,
                "parent": self.func_ids[id(f.parent)] if f.parent is not None else None,
                "ordinal": f.ordinal,
                "parameters": self.params_by_func[id(f)],
                "hash_full": canon_norm_hash(extent),
                "hash_body": body_norm_hash(body),
                "hash_raw": raw_hash(extent),
                "facts": facts,
            })
        symbols.sort(key=lambda r: (r["id"], r["offset"]))

        edges = sorted(self.edges.values(), key=lambda r: (r["from"], r["to"]))
        for e in edges:
            e["code"] = "PSS2001"

        closures = sorted(self.closures, key=lambda r: r["id"])
        # PSS4003.named_by_literal (SPEC 4.4, F1/P22): sourced from the
        # PSS3001 population only. A comment cannot produce a PSS3001 record
        # (comments are stripped before any fact is derived, SPEC 2), so a
        # name mentioned only in a comment correctly yields False here - the
        # tool has no notion of "comment evidence" to draw on, by design.
        literal_named_ids = set(
            r["matches"] for r in self.soft_refs if r["code"] == "PSS3001")
        no_caller = [
            {"code": "PSS4003", "id": fid,
             "named_by_literal": fid in literal_named_ids}
            for fid in sorted(
                self.func_ids[id(f)] for f in self.funcs
                if not self.radj.get(self.func_ids[id(f)]))]
        groups = [{"code": "PSS4004", "members": sorted(g)}
                  for g in self.sccs if len(g) > 1]
        groups.sort(key=lambda r: r["members"])

        script_records = sorted(self.script_records, key=lambda r: (r["id"], r["offset"]))
        usage_records = []
        for low in sorted(self.usage):
            u = self.usage[low]
            usage_records.append({
                "record": "usage_map", "code": "PSS2008", "id": u["id"],
                "name": u["name"],
                "writers": sorted(u["writers"]), "readers": sorted(u["readers"]),
                "writer_count": u["writer_count"], "reader_count": u["reader_count"],
            })

        local_records = sorted(self.local_aggregates.values(), key=lambda r: r["owner"])
        if "local-sites" in self.axes:
            local_records = local_records + sorted(
                self.detail_records, key=lambda r: (r["owner"], r["offset"]))

        model = {
            "pss_version": __version__,
            "model_version": MODEL_VERSION,
            "source": {
                "path": self.path,
                "sha256": hashlib.sha256(self.text.encode('utf-8')).hexdigest(),
                "line_count": len(self.lines.starts),
                "byte_count": len(self.text.encode('utf-8')),
            },
            # SPEC 5.6: the resolved axis set in sorted order, so a caller (or
            # `compare`) can tell what this model does and does not carry
            # without re-deriving it from which fields happen to be present.
            "materialization": {"axes": sorted(self.axes)},
            "counters": dict(sorted(self.counters.items())),
            "symbols": self._emit(symbols),
            "edges": self._emit(edges),
            "closures": self._emit(closures + no_caller + groups),
            "script_variables": self._emit(script_records + usage_records),
            "string_interpolation_references": self._emit(sorted(
                self.interp_records, key=lambda r: r["offset"])),
            "local_variables": self._emit(local_records),
            "soft_references": self._emit(sorted(
                self.soft_refs, key=lambda r: (r["code"], r["offset"]))),
            # SPEC 15.4 F2 / P23: a per-name aggregate is always present
            # (mirrors local_variables' per-function aggregate, SPEC 5.3);
            # per-site records are restored by the command-sites axis
            # (mirrors local-sites, SPEC 5.6). Same collection, two record
            # shapes, discriminated by "record" - the established idiom,
            # not a second mechanism.
            "unresolved_named_commands": self._emit(self._unresolved_command_records()),
            "limitations": self._emit(sorted(
                self.limitations,
                key=lambda r: (r["code"], r.get("line", 0), r.get("owner", "")))),
        }
        if with_cost:
            model[COST_KEY] = cost_block(model, self._axis_increments(model))
        return model

    def _axis_increments(self, model):
        """Bytes each axis would add to this model, measured not estimated.

        An axis already materialised adds nothing and is reported as zero
        without work. An absent one is priced by re-running the survey with it,
        because the axes are decided during extraction (SPEC 5.6) and their
        contribution is not recoverable from a model that lacks them. That is
        the cost of pricing a request honestly; guessing it would put a figure
        in the model that no derivation reproduces.
        """
        base = compact_bytes(model)
        out = {}
        for axis in sorted(AXES):
            if axis in self.axes:
                out[axis] = 0
                continue
            wider = Survey(self.path, self.text,
                           axes=self.axes | {axis}).run().model(with_cost=False)
            out[axis] = compact_bytes(wider) - base
        return out


def _tarjan_scc(adj, nodes):
    """Strongly-connected components. The call graph is NOT acyclic (SPEC 11.2),
    so every traversal here carries a visited set and terminates on revisit."""
    index = {}
    low = {}
    on_stack = {}
    stack = []
    result = []
    counter = [0]

    for root in nodes:
        if root in index:
            continue
        work = [(root, iter(sorted(adj.get(root, ()))))]
        index[root] = low[root] = counter[0]
        counter[0] += 1
        stack.append(root)
        on_stack[root] = True
        while work:
            node, it = work[-1]
            advanced = False
            for nxt in it:
                if nxt not in index:
                    index[nxt] = low[nxt] = counter[0]
                    counter[0] += 1
                    stack.append(nxt)
                    on_stack[nxt] = True
                    work.append((nxt, iter(sorted(adj.get(nxt, ())))))
                    advanced = True
                    break
                if on_stack.get(nxt):
                    low[node] = min(low[node], index[nxt])
            if advanced:
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
            if low[node] == index[node]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack[w] = False
                    comp.append(w)
                    if w == node:
                        break
                result.append(comp)
    return result


# ---------------------------------------------------------------------------
# Text rendering
# ---------------------------------------------------------------------------
def render_text(model):
    out = []
    src = model["source"]
    c = model["counters"]
    refs = [r for r in model["script_variables"] if r["record"] == "reference"]
    usage = [r for r in model["script_variables"] if r["record"] == "usage_map"]
    out.append("==== pss.py survey ====")
    out.append("source     : %s" % src["path"])
    out.append("sha256     : %s" % src["sha256"][:16])
    out.append("lines      : %d" % src["line_count"])
    out.append("")
    out.append("-- PSS1xxx definition inventory --")
    out.append("functions             : %d" % len(model["symbols"]))
    out.append("nested definitions    : %d" % sum(
        1 for s in model["symbols"] if "PSS1004" in s["facts"]))
    out.append("duplicate names       : %d" % sum(
        1 for s in model["symbols"] if "PSS1005" in s["facts"]))
    out.append("")
    out.append("-- PSS2xxx reference and binding --")
    out.append("named commands        : %d" % c["commands_named"])
    out.append("call edges            : %d" % len(model["edges"]))
    out.append("  from a function     : %d" % sum(
        1 for e in model["edges"] if e["from"] != "<script>"))
    out.append("variable references   : %d" % c["variable_refs"])
    out.append("scope-qualified refs  : %d" % len(refs))
    out.append("interpolated refs     : %d  (PSS2007, in %d expandable strings)" % (
        len(model["string_interpolation_references"]), c["expandable_strings"]))
    out.append("usage-map population  : %d  (PSS2008)" % len(usage))
    out.append("unresolved reads      : %d  (PSS9004)" % sum(
        1 for r in model["limitations"] if r["code"] == "PSS9004"))
    out.append("")
    out.append("-- PSS3xxx soft reference --")
    for code, label in (("PSS3001", "function-name lits"), ("PSS3002", "script-var lits")):
        hits = [r for r in model["soft_references"] if r["code"] == code]
        out.append("%-21s : %d  (quoted %d / bareword %d)" % (
            label, len(hits),
            sum(1 for r in hits if r["literal_kind"] == "quoted"),
            sum(1 for r in hits if r["literal_kind"] == "bareword")))
    out.append("string constants      : %d  (quoted %d / bareword %d)" % (
        c["string_literals_quoted"] + c["string_literals_bareword"],
        c["string_literals_quoted"], c["string_literals_bareword"]))
    out.append("")
    out.append("-- PSS4xxx impact closure --")
    out.append("no static caller      : %d" % sum(
        1 for r in model["closures"] if r.get("code") == "PSS4003"))
    out.append("recursion groups      : %d" % sum(
        1 for r in model["closures"] if r.get("code") == "PSS4004"))
    out.append("closure entries       : %d" % sum(
        r.get("transitive_callee_count", 0) for r in model["closures"]))
    out.append("")
    out.append("-- PSS9xxx analysis limitations --")
    by_code = {}
    for r in model["limitations"]:
        by_code[r["code"]] = by_code.get(r["code"], 0) + 1
    if by_code:
        for code in sorted(by_code):
            out.append("%-8s : %d  %s" % (code, by_code[code], FACTS[code]))
    else:
        out.append("(none)")
    out.append("")
    out.append("These are facts, not findings. No severity is assigned and no")
    out.append("verdict is implied; the exit code is 0 either way (SPEC 9).")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# --self-check (SPEC 13)
# ---------------------------------------------------------------------------
def self_check():
    here = os.path.dirname(os.path.abspath(__file__))
    spec_path = os.path.join(here, "SPEC.md")
    print("==== pss.py --self-check ====")
    print("  pss.py   : %s" % os.path.join(here, "pss.py"))
    print("  SPEC.md  : %s" % spec_path)
    if not os.path.exists(spec_path):
        print("  FAIL: SPEC.md not found next to pss.py")
        return EXIT_ERROR
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = fh.read()
    start = spec.find("## 4. Fact specifications")
    end = spec.find("## 5. Model format")
    if start < 0 or end < 0 or end <= start:
        print("  FAIL: could not locate SPEC section 4")
        return EXIT_ERROR
    section = spec[start:end]
    spec_codes = set(re.findall(r'`(PSS\d{4})`', section))
    code_codes = set(FACTS)
    print("  codes    : %d in FACTS, %d in SPEC.md section 4" % (len(code_codes), len(spec_codes)))
    missing_in_code = sorted(spec_codes - code_codes)
    missing_in_spec = sorted(code_codes - spec_codes)
    rc = EXIT_OK
    if missing_in_code:
        print("  FAIL: in SPEC.md but not compiled into pss.py: %s" % ", ".join(missing_in_code))
        rc = EXIT_ERROR
    if missing_in_spec:
        print("  FAIL: compiled into pss.py but absent from SPEC.md section 4: %s"
              % ", ".join(missing_in_spec))
        rc = EXIT_ERROR

    # Provisional-revision index (SPEC Appendix F). Reported, never fatal: the
    # exit code carries no verdict (SPEC 9). The gate that must be zero is
    # manifest registration, not this one.
    inline = set(re.findall(r'\[PROVISIONAL (P\d\d) ', spec))
    fstart = spec.find("## Appendix F")
    if fstart < 0:
        if inline:
            print("  FAIL: %d provisional marker(s) but no Appendix F" % len(inline))
            rc = EXIT_ERROR
    else:
        indexed = set(re.findall(r'^\| (P\d\d) \|', spec[fstart:], re.M))
        orphan_marker = sorted(inline - indexed)
        orphan_index = sorted(indexed - inline)
        if orphan_marker:
            print("  FAIL: marked in the body but absent from Appendix F: %s"
                  % ", ".join(orphan_marker))
            rc = EXIT_ERROR
        if orphan_index:
            print("  FAIL: listed in Appendix F but no marker in the body: %s"
                  % ", ".join(orphan_index))
            rc = EXIT_ERROR
        if not orphan_marker and not orphan_index:
            # A pending revision is normal work in progress and does not change
            # the exit code. A mismatch above IS a defect in this tool or its
            # SPEC, and exits non-zero - which does not conflict with SPEC 9,
            # because that rule forbids a verdict about the SURVEYED SCRIPT, not
            # the reporting of an internal inconsistency.
            print("  provisional: %d revision(s) pending review, index consistent"
                  % len(inline))
            if inline:
                print("             (Appendix F must be empty before manifest "
                      "registration)")

    vectors = [
        ("GV-1 empty", "", "e3b0c44298fc1c14"),
        ("GV-2 simple", "function Foo { $X }", "f36eed9db4380dae"),
        ("GV-3 comment-cancels",
         "function Foo {\n    # a comment\n    $X\n}", "f36eed9db4380dae"),
        ("GV-4 string-literal",
         'function Bar { Write-Output "hello world" }', "f8749da115ef182a"),
        ("GV-5 here-string",
         'function Baz {\n    $t = @"\nline1\nline2\n"@\n    $t\n}',
         "a65ca2f4b74efce1"),
    ]
    bad = 0
    for name, body, expected in vectors:
        got = canon_norm_hash(body)
        if got != expected:
            print("  FAIL: shared golden vector %s: expected %s got %s" % (name, expected, got))
            bad += 1
    if bad:
        rc = EXIT_ERROR
    else:
        print("  hash_full: %d/%d shared ADR 0015 golden vectors reproduced" % (
            len(vectors), len(vectors)))

    # hash_body must NOT equal hash_full where a string literal is present:
    # that divergence is the whole point of SPEC 10.3.
    a = 'function A { Write-Output "alpha" }'
    b = 'function A { Write-Output "beta" }'
    if canon_norm_hash(a) != canon_norm_hash(b):
        print("  FAIL: hash_full should be blind to string contents")
        rc = EXIT_ERROR
    if body_norm_hash(a) == body_norm_hash(b):
        print("  FAIL: hash_body must distinguish functions differing only by a string")
        rc = EXIT_ERROR
    if rc == EXIT_OK:
        print("  hash_body: string-literal sensitivity confirmed (SPEC 10.3)")

    # Axis vocabulary (SPEC 5.6): the AXES dict compiled into pss.py against
    # the SPEC 5.6 table, in both directions.
    astart = spec.find("### 5.6 Materialisation axes")
    aend = spec.find("### 5.7")
    if astart < 0 or aend < 0 or aend <= astart:
        print("  FAIL: could not locate SPEC section 5.6")
        rc = EXIT_ERROR
    else:
        asection = spec[astart:aend]
        spec_axes = set(re.findall(r'^\| `([a-z-]+)` \|', asection, re.M))
        code_axes = set(AXES)
        axis_missing_in_code = sorted(spec_axes - code_axes)
        axis_missing_in_spec = sorted(code_axes - spec_axes)
        if axis_missing_in_code:
            print("  FAIL: axis in SPEC.md 5.6 but not compiled into pss.py: %s"
                  % ", ".join(axis_missing_in_code))
            rc = EXIT_ERROR
        if axis_missing_in_spec:
            print("  FAIL: axis compiled into pss.py but absent from SPEC.md 5.6: %s"
                  % ", ".join(axis_missing_in_spec))
            rc = EXIT_ERROR
        if not axis_missing_in_code and not axis_missing_in_spec:
            print("  axes     : %d in AXES, %d in SPEC.md section 5.6, agree"
                  % (len(code_axes), len(spec_axes)))

    if rc == EXIT_OK:
        print("")
        print("  SPEC.md and FACTS are in sync (no drift detected)")
    return rc


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def read_source(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return data.decode("utf-8", errors="replace")


def _write_model(model, args):
    """Shared 'print or write' tail for any subcommand that emits a model.

    Compact JSON by default. SPEC 2.4 asks the model to be readable, which is
    a property of self-describing keys, not of indentation; the indentation
    cost 600 KB on the reference target.
    """
    if args.format == "json" or args.out:
        if args.pretty:
            payload = json.dumps(model, indent=2, ensure_ascii=False)
        else:
            payload = json.dumps(model, separators=(',', ':'), ensure_ascii=False)
        if args.out:
            with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(payload + "\n")
            if args.format == "text":
                print(render_text(model))
                print("")
                print("model written to %s" % args.out)
        else:
            print(payload)
    else:
        print(render_text(model))
    return EXIT_OK


def cmd_survey(args):
    path = args.script
    if not path.lower().endswith(".ps1"):
        sys.stderr.write("pss.py: only .ps1 is in scope; .psm1 and .psd1 are out "
                         "of scope (SPEC 1.4)\n")
        return EXIT_ERROR
    if not os.path.isfile(path):
        sys.stderr.write("pss.py: not a readable file: %s\n" % path)
        return EXIT_ERROR
    try:
        axes = parse_axes_arg(args.axes)
    except ValueError as exc:
        sys.stderr.write("pss.py: --axes: %s\n" % exc)
        return EXIT_ERROR
    text = read_source(path)
    survey = Survey(path, text, axes=axes).run()
    model = survey.model()
    if getattr(args, "cost", False):
        # The same derivation with the model discarded, rather than a second
        # one that can drift from the block every model carries (SPEC 3.1).
        payload = model[COST_KEY]
        if args.format == "json":
            text_out = json.dumps(payload, indent=2, ensure_ascii=False) \
                if args.pretty else json.dumps(payload, separators=(',', ':'),
                                               ensure_ascii=False)
        else:
            text_out = _cost_text(payload)
        sys.stdout.write(text_out + "\n")
        return 0
    return _write_model(model, args)


def _cost_text(payload):
    """The text channel of the cost report. Every value printed here is a value
    in the JSON payload, per SPEC 13.2's channel-agreement requirement; nothing
    is computed on the way out."""
    lines = ["cost report (%s; %s)" % (payload["format"], payload["measured"]),
             "source sha256 : %s" % payload["source_sha256"],
             "model bytes   : %d" % payload["model_bytes"], "",
             "by collection:"]
    for row in payload["by_collection"]:
        lines.append("  %-32s %10d bytes  %8d records"
                     % (row["collection"], row["bytes"], row["records"]))
    lines.append("  %-32s %10d bytes" % ("envelope", payload["envelope"]["bytes"]))
    lines.append("")
    lines.append("axis increment:")
    for row in payload["axis_increment"]:
        lines.append("  %-32s %10s bytes"
                     % (row["axis"],
                        "unpriced" if row["bytes"] is None else row["bytes"]))
    return "\n".join(lines)


def _model_has_symbol(model, scope):
    """Whether `scope` is a genuine symbol identifier in this model (SPEC
    5.7): present as an `id` in `symbols` or in `script_variables`. Refusing
    an unmatched scope, rather than emitting an all-empty model, keeps a typo
    from reading as "this symbol has no facts" (SPEC 1.3: fact, not a guess
    dressed as one)."""
    for rec in model.get("symbols", ()):
        if rec.get("id") == scope:
            return True
    for rec in model.get("script_variables", ()):
        if rec.get("id") == scope:
            return True
    return False


def _record_in_scope(r, scope):
    """SPEC 5.7's single mechanical membership rule, applied identically
    across every collection: a record participates when it carries `scope`
    in one of a fixed set of identifying fields. No collection-specific
    special-casing - the same rule reads a closure's `id`, an edge's `from`/
    `to`, a reference site's `owner`, a soft reference's `matches`, an SCC
    group's `members`, and an unresolved-command aggregate's `owners`,
    because those are exactly the fields that already carry a symbol
    identifier elsewhere in this model (SPEC 5.2)."""
    if r.get("id") == scope or r.get("from") == scope or r.get("to") == scope:
        return True
    if r.get("owner") == scope or r.get("matches") == scope:
        return True
    for field in ("members", "owners"):
        values = r.get(field)
        if values is not None and scope in values:
            return True
    return False


# Collections a --scope projection filters. `limitations` is deliberately
# absent: SPEC 5.7 keeps it in full, unconditionally, because it describes
# what could NOT be determined and filtering it would misrepresent the
# projection's own coverage. `counters` and `source` are whole-survey
# metadata, not per-symbol, and pass through via the shallow copy below.
_SCOPED_COLLECTIONS = (
    "symbols", "edges", "closures", "script_variables",
    "string_interpolation_references", "local_variables",
    "soft_references", "unresolved_named_commands",
)


def slice_model(model, scope=None, axes=None):
    """SPEC 5.7 (symbol-scoped projection) and SPEC 5.5/P21 (axis-set
    normalisation) unified into one deterministic reduction (P20/P21): both
    narrow an EXISTING model by a fixed, factual rule, and both must declare
    the narrowing in the output's own `materialization` block so the result
    cannot be mistaken for a whole model (SPEC 5.6).

    `axes`, if not None, is the exact axis subset to keep; the caller
    (cmd_slice) has already verified it is a subset of what the input model
    carries, so this function only ever removes materialised fields, never
    synthesises fields that were never captured.
    """
    out = dict(model)
    materialization = dict(model.get("materialization", {"axes": []}))
    materialization["axes"] = list(materialization.get("axes", []))

    if axes is not None:
        current = frozenset(materialization["axes"])
        dropped = current - frozenset(axes)
        if "closure-sets" in dropped and "closures" in out:
            out["closures"] = [
                {k: v for k, v in r.items()
                 if k not in ("transitive_callees", "transitive_callers")}
                for r in out["closures"]]
        if "local-sites" in dropped and "local_variables" in out:
            out["local_variables"] = [
                r for r in out["local_variables"] if r.get("record") != "reference"]
        if "command-sites" in dropped and "unresolved_named_commands" in out:
            out["unresolved_named_commands"] = [
                r for r in out["unresolved_named_commands"] if r.get("record") != "site"]
        materialization["axes"] = sorted(axes)

    if scope is not None:
        if not _model_has_symbol(model, scope):
            raise ValueError("--scope %s matches no symbol identifier in this model"
                             % scope)
        for key in _SCOPED_COLLECTIONS:
            if key in out:
                out[key] = [r for r in out[key] if _record_in_scope(r, scope)]
        materialization["scope"] = scope

    out["materialization"] = materialization
    # A sliced model is a model, so it carries a cost block describing itself
    # rather than the model it came from. An axis it no longer carries cannot
    # be priced from a model alone - the axes are decided during extraction
    # (SPEC 5.6) - so that increment is reported as null rather than carried
    # over, which would state a figure about a different artefact.
    out.pop(COST_KEY, None)
    kept = frozenset(materialization.get("axes", ()))
    out[COST_KEY] = cost_block(
        out, {axis: (0 if axis in kept else None) for axis in AXES})
    return out


def cmd_slice(args):
    if not args.scope and not args.axes:
        sys.stderr.write("pss.py: slice: at least one of --scope or --axes is required\n")
        return EXIT_ERROR
    if not os.path.isfile(args.model):
        sys.stderr.write("pss.py: not a readable file: %s\n" % args.model)
        return EXIT_ERROR
    with open(args.model, "r", encoding="utf-8") as fh:
        try:
            model = json.load(fh)
        except json.JSONDecodeError as exc:
            sys.stderr.write("pss.py: slice: %s is not valid JSON (%s)\n" % (args.model, exc))
            return EXIT_ERROR

    current_axes = frozenset(model.get("materialization", {}).get("axes", []))
    requested_axes = None
    if args.axes is not None:
        if args.axes.strip() == "all":
            # 'all' on slice means "every axis the INPUT has", not the global
            # vocabulary (survey's 'all') - slice never adds material.
            requested_axes = current_axes
        else:
            try:
                requested_axes = parse_axes_arg(args.axes)
            except ValueError as exc:
                sys.stderr.write("pss.py: --axes: %s\n" % exc)
                return EXIT_ERROR
            not_present = sorted(requested_axes - current_axes)
            if not_present:
                sys.stderr.write(
                    "pss.py: slice: --axes requests %s, which the input model "
                    "does not carry (input has: %s). An axis only restores "
                    "what a survey already materialised; slice cannot add "
                    "material a survey never captured.\n"
                    % (", ".join(not_present), ", ".join(sorted(current_axes)) or "(none)"))
                return EXIT_ERROR

    try:
        sliced = slice_model(model, scope=args.scope, axes=requested_axes)
    except ValueError as exc:
        sys.stderr.write("pss.py: slice: %s\n" % exc)
        return EXIT_ERROR

    return _write_model(sliced, args)


def cmd_compare(args):
    sys.stderr.write(
        "pss.py: 'compare' (Layer 3) is not implemented in version %s.\n"
        "        The comparator arrives in a later patch of this series; this\n"
        "        build ships Layer 1 and Layer 2 only. Refusing rather than\n"
        "        emitting an empty comparison, which would read as 'no change'.\n"
        % __version__)
    return EXIT_ERROR


def cmd_list_facts(_args):
    print("==== pss.py fact catalogue (%d codes) ====" % len(FACTS))
    blocks = {
        "1": "PSS1xxx  definition inventory        (survey)",
        "2": "PSS2xxx  reference and binding       (survey)",
        "3": "PSS3xxx  soft reference              (survey)",
        "4": "PSS4xxx  impact closure              (survey)",
        "6": "PSS6xxx  presence transition         (compare)",
        "7": "PSS7xxx  attribute change            (compare)",
        "8": "PSS8xxx  graph / rename-omission     (compare)",
        "9": "PSS9xxx  analysis limitation         (both)",
    }
    current = None
    for code in sorted(FACTS):
        block = code[3]
        if block != current:
            current = block
            print("")
            print(blocks[block])
        print("  %-8s %s" % (code, FACTS[code]))
    print("")
    print("No code carries a severity. No code implies a verdict (SPEC 1.2).")
    return EXIT_OK


def parse_axes_arg(raw):
    """Parse a comma-separated --axes value against the SPEC 5.6 vocabulary.

    Returns a frozenset. `None` or '' means no axes (SPEC 5.6: "no axes
    resolves to an empty list"). The literal 'all' resolves to the full
    vocabulary and must appear alone - mixing it with a named axis is not
    obviously a superset or a mistake, so it is refused rather than guessed.
    An unrecognised name is a usage error (SPEC 5.6): the caller raises
    ValueError with the full valid vocabulary printed, rather than being
    silently ignored or treated as a no-op.
    """
    if not raw:
        return frozenset()
    tokens = [t.strip() for t in raw.split(",") if t.strip()]
    if "all" in tokens:
        if len(tokens) > 1:
            raise ValueError("'all' must be used alone, not combined with named axes")
        return frozenset(AXES)
    unknown = sorted(t for t in tokens if t not in AXES)
    if unknown:
        raise ValueError(
            "unrecognised axis name(s): %s (valid: %s, or 'all')"
            % (", ".join(unknown), ", ".join(sorted(AXES))))
    return frozenset(tokens)


def build_parser():
    p = argparse.ArgumentParser(
        prog="pss.py",
        description="PowerShell Symbol Surveyor - facts about symbols and their change.")
    p.add_argument("--version", action="store_true", help="print version and exit")
    p.add_argument("--list-facts", action="store_true", help="print the fact catalogue and exit")
    p.add_argument("--self-check", action="store_true",
                   help="verify SPEC section 4 against the compiled catalogue and exit")
    sub = p.add_subparsers(dest="command")

    sp = sub.add_parser("survey", help="survey a single .ps1 and emit the symbol model")
    sp.add_argument("script")
    sp.add_argument("--out", help="write the model to PATH (default: stdout)")
    sp.add_argument("--format", choices=("text", "json"), default="text")
    sp.add_argument("--axes", metavar="AXES",
                    help="comma-separated materialisation axes to restore "
                         "(%s, or 'all'; default: none, SPEC 5.6)"
                         % ", ".join(sorted(AXES)))
    sp.add_argument("--cost", action="store_true",
                    help="emit only the cost report for this request and exit; "
                         "the model is computed and discarded (SPEC 3.1)")
    sp.add_argument("--pretty", action="store_true",
                    help="indent the JSON model (default is compact)")
    sp.set_defaults(func=cmd_survey)

    cp = sub.add_parser("compare", help="compare two models and emit delta facts")
    cp.add_argument("before")
    cp.add_argument("after")
    cp.add_argument("--format", choices=("text", "json"), default="text")
    cp.set_defaults(func=cmd_compare)

    lp = sub.add_parser("slice", help="reduce a stored model deterministically "
                                       "(symbol scope and/or a narrower axis set)")
    lp.add_argument("model", help="path to a model produced by 'survey'")
    lp.add_argument("--scope", metavar="ID",
                    help="keep only records concerning this symbol identifier, "
                         "plus incident edges and all limitations (SPEC 5.7)")
    lp.add_argument("--axes", metavar="AXES",
                    help="narrow to this axis subset of what the input model "
                         "already carries (comma-separated, or 'all' to keep "
                         "every axis the input has; SPEC 5.5/P21)")
    lp.add_argument("--out", help="write the sliced model to PATH (default: stdout)")
    lp.add_argument("--format", choices=("text", "json"), default="text")
    lp.add_argument("--pretty", action="store_true",
                    help="indent the JSON model (default is compact)")
    lp.set_defaults(func=cmd_slice)
    return p


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write("pss.py requires Python %d.%d or later (running %d.%d)\n" % (
            MIN_PYTHON[0], MIN_PYTHON[1], sys.version_info[0], sys.version_info[1]))
        return EXIT_ERROR
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.version:
        print("pss.py %s (model_version %s)" % (__version__, MODEL_VERSION))
        return EXIT_OK
    if args.list_facts:
        return cmd_list_facts(args)
    if args.self_check:
        return self_check()
    if not getattr(args, "command", None):
        parser.print_help()
        return EXIT_ERROR
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
