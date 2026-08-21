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

__version__ = "0.5.0"
MODEL_VERSION = "5"

MIN_PYTHON = (3, 12)

# ---------------------------------------------------------------------------
# Materialisation axes (SPEC 5.6). The vocabulary is closed: --self-check
# verifies these names against the SPEC 5.6 table in both directions. A
# master collection never becomes an axis (SPEC 5.6); an axis only restores
# content already withheld *within* a collection that is always present.
# ---------------------------------------------------------------------------
# SPEC 3.1 (round-4 F4): the tool's GLOBAL flag surface, declared once and
# read twice - build_parser() constructs each flag from this dict and the
# descriptor serialises it, so the parser and the published interface cannot
# name different surfaces. A round-4 reviewer found the descriptor silent on
# exactly these entry points: the README taught them, which is the "copy of
# the documentation" the 3.1 property exists to remove. (test_pss.py's own
# --emit-baseline-digest is the GATE's surface, not this tool's, and is
# deliberately outside this declaration.)
GLOBAL_FLAGS = {
    "--version": "print version and exit",
    "--list-facts": "print the fact catalogue and exit",
    "--self-check": "verify SPEC section 4 against the compiled catalogue "
                    "and exit",
    "--capabilities": "print the machine-readable interface descriptor "
                      "(JSON) and exit (SPEC 3.1)",
}

# SPEC 5.6 / 3.1 (round-4 F4): the one axis alias, declared where the axes
# are. parse_axes_arg and cmd_slice both read this constant, and the
# descriptor serialises it - previously 'all' lived as a bare literal in the
# implementation and the README, invisible to the descriptor.
AXES_ALIAS = {
    "all": "the full SPEC 5.6 vocabulary on survey; every axis the input "
           "already carries on slice (a slice never adds material, SPEC "
           "5.7); must appear alone, never combined with named axes",
}

AXES = {
    "closure-sets": "transitive_callees and transitive_callers on each closure record",
    "local-sites": "one record per function-local variable reference",
    "command-sites": "one record per unresolved command-invocation site - "
                     "carrying the argument itemisation and source span - "
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
    "PSS6001": "A name present in model A is absent from model B.",
    "PSS6002": "A name absent from model A is present in model B.",
    "PSS6003": "A name is present in both models.",
    # PSS7xxx - attribute change (compare)
    "PSS7001": "Hash-triple classification.",
    "PSS7002": "Parameter signature equality.",
    "PSS7003": "Callee set equality.",
    "PSS7004": "Caller set equality.",
    "PSS7005": "Dependency classification.",
    "PSS7006": "Combined classification.",
    "PSS7007": "A script-scope variable's usage map differs between the models.",
    # PSS8xxx - graph, closure and rename-omission change (compare)
    "PSS8001": "A call edge present in model B and absent from model A.",
    "PSS8002": "A call edge present in model A and absent from model B.",
    "PSS8003": "A function's transitive closure differs between models.",
    "PSS8004": "A soft reference's resolution state differs between the models.",
    "PSS8005": "Incomplete-rename candidate.",
    "PSS8006": "Producer/consumer desynchronisation candidate.",
    "PSS8007": "A script-scope variable read in model B with no write site retained in it.",
    "PSS8008": "A function's PSS4003 presence differs between the models.",
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

# The common parameters that declare a variable in the calling scope
# (SPEC 12.2). The parameter word is matched lower-cased; the value token
# names the variable, with a leading `+` (the append form) stripped.
_OUTVAR_PARAMS = frozenset((
    "-outvariable", "-errorvariable", "-warningvariable",
    "-informationvariable", "-pipelinevariable",
))

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
    assignment operator; and after the keyword `in` inside a `foreach`
    condition group - `foreach ($x in Get-Thing)` is a genuine pipeline at run
    time, and the reference parser counts its head as a command ([F4], D10).
    Three exclusions keep the population equal to what the reference parser
    calls a command name:

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
    # Each entry is the lower-cased keyword the group was opened after, or
    # None. Truthiness carries the old "opened after a keyword" meaning; the
    # text itself is read by exactly one rule, the `in`-in-`foreach` one.
    paren_stack = []
    prev_kw = None
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
                opened_after_keyword = paren_stack.pop() if paren_stack else None
                prev_kw = None
                if opened_after_keyword:
                    cmd_pos = True
                    continue
        prev_kw = (t.text.lower()
                   if t.kind == 'word' and t.text.lower() in KEYWORDS else None)
        if t.kind == 'word':
            low = t.text.lower()
            # SPEC 10.6 dotted command names (D12): `dism.exe` tokenizes as
            # word `.` word, and pre-D12 the yielded command name was the
            # first word alone - the PSS2009 record named `dism`, a name that
            # exists in no source line. In command position an ADJACENT run
            # of word ('.' word|num)* is one name; adjacency is checked on
            # byte offsets, never on significant-token order, so `dism . exe`
            # (the command `dism` with two arguments) does not join. A name
            # whose FIRST segment leads with a digit (`7z.exe`) tokenizes as
            # `num` and is not a command word at all - a stated limit of the
            # lexer, not of this join (SPEC 10.6).
            joined, j = t, k
            if cmd_pos and low not in KEYWORDS and not low.startswith('-') \
                    and bracket_depth == 0:
                while j + 2 < len(sig):
                    dot = toks[sig[j + 1]]
                    tail = toks[sig[j + 2]]
                    if not (dot.kind == 'op' and dot.text == '.'
                            and dot.start == joined.end
                            and tail.kind in ('word', 'num')
                            and tail.start == dot.end):
                        break
                    joined = Tok('word', joined.text + '.' + tail.text,
                                 joined.start, tail.end)
                    j += 2
            nxt_eff = toks[sig[j + 1]] if j + 1 < len(sig) else nxt
            excluded = (
                low in KEYWORDS
                or low.startswith('-')
                or bracket_depth > 0
                or (nxt_eff is not None and nxt_eff.kind == 'op'
                    and nxt_eff.text in ('=', '+=', '-=', '*=', '/=', '%='))
            )
            if cmd_pos and not excluded:
                yield k, joined
            if low in STATEMENT_KEYWORDS:
                cmd_pos = True
                continue
            if low == 'in' and paren_stack and paren_stack[-1] == 'foreach':
                # SPEC 10.6 [F4]: the collection expression of a `foreach`
                # condition starts here. Scoped to the innermost group being
                # the `foreach` one, so a bareword `in` used as an ordinary
                # argument opens nothing.
                cmd_pos = True
                continue
        if t.kind == 'nl':
            cmd_pos = True
        elif t.kind == 'op' and (t.text in _CMD_POS_OPS or t.text == '}'):
            cmd_pos = True
        else:
            cmd_pos = False


def _dynamic_target(toks, r):
    """The name expression following a dynamic-invocation operator (SPEC 4.8,
    D12): the var or parenthesised expression at raw index ``r``, extended
    over byte-ADJACENT member/static-member/index/call tails - the same
    adjacency discipline as the 10.6 dotted-name join, so ``& $x.Path``
    records ``$x.Path`` while ``& $x .Path`` (the command held in ``$x`` with
    an argument) records ``$x``. Balance is walked over TOKENS, so a paren
    inside a string literal cannot derail it. Returns ``(start, end)`` byte
    offsets into the source.
    """
    def balanced(i, open_c, close_c):
        depth = 0
        while i < len(toks):
            t = toks[i]
            if t.kind == 'op' and t.text == open_c:
                depth += 1
            elif t.kind == 'op' and t.text == close_c:
                depth -= 1
                if depth == 0:
                    return i
            i += 1
        return None

    t0 = toks[r]
    if t0.kind == 'op' and t0.text == '(':
        close = balanced(r, '(', ')')
        end = close if close is not None else r
    else:
        end = r
        while end + 1 < len(toks):
            nt = toks[end + 1]
            if nt.start != toks[end].end:
                break
            if nt.kind == 'op' and nt.text in ('.', '::') \
                    and end + 2 < len(toks) \
                    and toks[end + 2].kind in ('word', 'num') \
                    and toks[end + 2].start == nt.end:
                end += 2
                continue
            if nt.kind == 'op' and nt.text in ('(', '['):
                close = balanced(end + 1, nt.text,
                                 ')' if nt.text == '(' else ']')
                if close is None:
                    break
                end = close
                continue
            break
    return t0.start, toks[end].end


def _command_arguments(text, toks, sig, k, head):
    """The argument tokens and source span of an unresolved invocation
    (SPEC 4.2 PSS2009, D12). ``k`` is the sig index of the command word;
    ``head`` is the (possibly dot-joined) command token.

    Itemisation, not binding: PowerShell binds positionally and by name
    against cmdlet metadata this tool does not hold, and guessing a binding
    would be a judgement (SPEC 1.2). Each item is ``{kind, text}`` verbatim;
    separator and redirection operators are not itemised, and the ``span``
    - [start, end) byte offsets over the whole invocation - is the ground
    truth the itemisation is a convenience over. A backtick continuation
    lives inside a ``bt`` token, so a multi-line invocation is one element
    and its span says so; two invocations on one line get two spans, which
    is the disambiguation a line number cannot give.
    """
    def balanced_sig(j, open_c, close_c):
        depth = 0
        while j < len(sig):
            tt = toks[sig[j]]
            if tt.kind == 'op' and tt.text == open_c:
                depth += 1
            elif tt.kind == 'op' and tt.text == close_c:
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return None

    def advance_past(j, end_off):
        while j < len(sig) and toks[sig[j]].start < end_off:
            j += 1
        return j

    args = []
    stop_ops = frozenset(('|', ';', ')', '}', '&', '&&', '||'))
    j = advance_past(k + 1, head.end)
    end_off = head.end
    while j < len(sig):
        t = toks[sig[j]]
        if t.kind == 'nl' or (t.kind == 'op' and t.text in stop_ops):
            break
        if t.kind == 'op' and t.text in ('(', '{'):
            close = balanced_sig(j, t.text, ')' if t.text == '(' else '}')
            if close is None:
                break
            ce = toks[sig[close]].end
            args.append({"kind": "expression" if t.text == '(' else
                         "scriptblock", "text": text[t.start:ce]})
            end_off = ce
            j = close + 1
            continue
        if t.kind == 'op' and t.text in ('$', '@') and j + 1 < len(sig) \
                and toks[sig[j + 1]].kind == 'op' \
                and toks[sig[j + 1]].text == '(' \
                and toks[sig[j + 1]].start == t.end:
            close = balanced_sig(j + 1, '(', ')')
            if close is None:
                break
            ce = toks[sig[close]].end
            args.append({"kind": "expression", "text": text[t.start:ce]})
            end_off = ce
            j = close + 1
            continue
        if t.kind == 'var':
            ts, te = _dynamic_target(toks, sig[j])
            args.append({"kind": "splat" if t.text.startswith('@')
                         else "variable", "text": text[ts:te]})
            end_off = te
            j = advance_past(j + 1, te)
            continue
        if t.kind == 'word':
            if t.text.startswith('-'):
                args.append({"kind": "parameter", "text": t.text})
                end_off = t.end
                j += 1
                continue
            ts, te = _dynamic_target(toks, sig[j])
            args.append({"kind": "bareword", "text": text[ts:te]})
            end_off = te
            j = advance_past(j + 1, te)
            continue
        if t.kind in ('str', 'estr', 'num'):
            kind = {"str": "string", "estr": "expandable_string",
                    "num": "number"}[t.kind]
            args.append({"kind": kind, "text": t.text})
            end_off = t.end
            j += 1
            continue
        # Any other operator (a comma, a redirection, a member dot that no
        # chain consumed) separates or decorates; it is covered by the span
        # and not itemised.
        end_off = t.end
        j += 1
    return args, [head.start, end_off]


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
        # The parameter's own var token IS its declaration site (SPEC 12.2).
        # Consumed by `_precompute_parameters` and stripped before the entry
        # reaches the model: `symbols[].parameters` records carry no offset.
        "offset": toks[sig[var_pos]].start,
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


# The key-path set the model emits (SPEC 13.3), declared rather than observed.
# The 13.1 fingerprint is taken over the paths a *given* model happens to carry,
# so an optional field the pinned generation never populates can appear or
# vanish without moving it. Two such fields exist, and they are the reason one
# corpus entry carries two fingerprints across its generations; each is marked
# "optional" with the evidence recorded in SPEC 13.3 rather than asserted.
#
#   always    - present in every model, at every materialisation
#   axis      - present only when its axis is materialised (SPEC 5.6)
#   optional  - data-dependent; present when the source populates it
#
# Declared here, not in SPEC.md, so that --capabilities can serialise this
# constant instead of restating it: the descriptor and the declaration are the
# same fact, and two copies of a fact drift (ADR 0036). --self-check holds this
# against the document, the way it already does for FACTS and AXES.
MODEL_SCHEMA = {
    "/closures": "always",
    "/closures[]/code": "always",
    "/closures[]/facts": "always",
    "/closures[]/id": "always",
    "/closures[]/members": "always",
    "/closures[]/named_by_literal": "always",
    "/closures[]/record": "always",
    "/closures[]/transitive_callee_count": "always",
    "/closures[]/transitive_callees": "axis",
    "/closures[]/transitive_caller_count": "always",
    "/closures[]/transitive_callers": "axis",
    "/cost": "always",
    "/cost/axis_increment": "always",
    "/cost/axis_increment[]/axis": "always",
    "/cost/axis_increment[]/bytes": "always",
    "/cost/by_collection": "always",
    "/cost/by_collection[]/bytes": "always",
    "/cost/by_collection[]/collection": "always",
    "/cost/by_collection[]/records": "always",
    "/cost/envelope": "always",
    "/cost/envelope/bytes": "always",
    "/cost/format": "always",
    "/cost/measured": "always",
    "/cost/model_bytes": "always",
    "/cost/source_sha256": "always",
    "/counters": "always",
    "/counters/assignments": "always",
    "/counters/commands_dynamic": "always",
    "/counters/commands_named": "always",
    "/counters/expandable_strings": "always",
    "/counters/interpolation_refs": "always",
    "/counters/string_literals_bareword": "always",
    "/counters/string_literals_quoted": "always",
    "/counters/unresolved_named_command_sites": "always",
    "/counters/variable_refs": "always",
    "/edges": "always",
    "/edges[]/code": "always",
    "/edges[]/from": "always",
    "/edges[]/lines": "always",
    "/edges[]/sites": "always",
    "/edges[]/to": "always",
    "/limitations": "always",
    "/limitations[]/code": "always",
    "/limitations[]/detail": "always",
    "/limitations[]/line": "always",
    "/limitations[]/owner": "always",
    "/limitations[]/target": "always",
    "/local_variables": "always",
    "/local_variables[]/automatic_refs": "always",
    "/local_variables[]/code": "axis",
    "/local_variables[]/id": "axis",
    "/local_variables[]/in_expandable_string": "axis",
    "/local_variables[]/rhs": "axis",
    "/local_variables[]/rhs_span": "axis",
    "/local_variables[]/line": "axis",
    "/local_variables[]/local_declared": "always",
    "/local_variables[]/local_refs": "always",
    "/local_variables[]/name": "axis",
    "/local_variables[]/owner": "always",
    "/local_variables[]/record": "always",
    "/local_variables[]/role": "axis",
    "/local_variables[]/unresolved_refs": "always",
    "/materialization": "always",
    "/materialization/axes": "always",
    "/model_version": "always",
    "/pss_version": "always",
    "/script_variables": "always",
    "/script_variables[]/code": "always",
    "/script_variables[]/id": "always",
    "/script_variables[]/in_expandable_string": "optional",
    "/script_variables[]/rhs": "optional",
    "/script_variables[]/rhs_span": "optional",
    "/script_variables[]/line": "always",
    "/script_variables[]/name": "always",
    "/script_variables[]/owner": "always",
    "/script_variables[]/qualifier": "always",
    "/script_variables[]/reader_count": "always",
    "/script_variables[]/readers": "always",
    "/script_variables[]/record": "always",
    "/script_variables[]/role": "always",
    "/script_variables[]/writer_count": "always",
    "/script_variables[]/writers": "always",
    "/soft_references": "always",
    "/soft_references[]/code": "always",
    "/soft_references[]/line": "always",
    "/soft_references[]/literal": "always",
    "/soft_references[]/literal_kind": "always",
    "/soft_references[]/matches": "always",
    "/soft_references[]/owner": "always",
    "/source": "always",
    "/source/byte_count": "always",
    "/source/line_count": "always",
    "/source/path": "always",
    "/source/sha256": "always",
    "/string_interpolation_references": "always",
    "/string_interpolation_references[]/code": "always",
    "/string_interpolation_references[]/id": "always",
    "/string_interpolation_references[]/in_expandable_string": "always",
    "/string_interpolation_references[]/line": "always",
    "/string_interpolation_references[]/name": "always",
    "/string_interpolation_references[]/owner": "always",
    "/string_interpolation_references[]/qualifier": "optional",
    "/string_interpolation_references[]/record": "always",
    "/string_interpolation_references[]/role": "always",
    "/symbols": "always",
    "/symbols[]/depth": "always",
    "/symbols[]/end_line": "always",
    "/symbols[]/facts": "always",
    "/symbols[]/hash_body": "always",
    "/symbols[]/hash_full": "always",
    "/symbols[]/hash_raw": "always",
    "/symbols[]/id": "always",
    "/symbols[]/kind": "always",
    "/symbols[]/name": "always",
    "/symbols[]/ordinal": "optional",
    "/symbols[]/parameters": "always",
    "/symbols[]/parameters[]/mandatory": "always",
    "/symbols[]/parameters[]/name": "always",
    "/symbols[]/parameters[]/position": "always",
    "/symbols[]/parameters[]/qualifier": "always",
    "/symbols[]/parameters[]/type": "always",
    "/symbols[]/parent": "always",
    "/symbols[]/record": "optional",
    "/symbols[]/start_line": "always",
    "/unresolved_named_commands": "always",
    "/unresolved_named_commands[]/arguments": "axis",
    "/unresolved_named_commands[]/arguments[]/kind": "axis",
    "/unresolved_named_commands[]/arguments[]/text": "axis",
    "/unresolved_named_commands[]/code": "always",
    "/unresolved_named_commands[]/line": "axis",
    "/unresolved_named_commands[]/name": "always",
    "/unresolved_named_commands[]/owner": "axis",
    "/unresolved_named_commands[]/owners": "always",
    "/unresolved_named_commands[]/record": "always",
    "/unresolved_named_commands[]/sites": "always",
    "/unresolved_named_commands[]/span": "axis",
}

MODEL_SCHEMA_KINDS = ("always", "axis", "optional")


# SPEC 13.3, value nullability. MODEL_SCHEMA says which key paths exist and
# when; it says nothing about what a value may be. Exactly these paths may
# carry JSON null, each with the fact its null states; every other path's
# value is never null - absence is expressed by omitting the key (kind
# `optional`), the model's existing size-driven convention (SPEC 4.4,
# `named_by_literal`: absent, never false). Null is reserved for the cases
# where the key must stay - a uniform record shape - and the value's
# unavailability is itself the fact.
#
# One copy of the fact (ADR 0036): --capabilities serialises this dict, and
# --self-check holds it against the SPEC 13.3 nullability table in both
# directions.
NULLABLE_PATHS = {
    "/symbols[]/parameters[]/qualifier":
        "the parameter is declared without a scope qualifier",
    "/symbols[]/parameters[]/type":
        "the parameter is declared without a type constraint",
    "/cost/axis_increment[]/bytes":
        "the model is a slice (SPEC 5.7) that no longer carries the axis, so "
        "the increment cannot be priced from this model (SPEC 5.6)",
}


# ---------------------------------------------------------------------------
# SPEC 13.3: the per-record presence contract (round-3 adjudication B1).
#
# MODEL_SCHEMA's kind `always` is a PER-MODEL claim - the path occurs in every
# model this build emits - and round 3 verified the cost of leaving the
# per-RECORD question undeclared: /symbols[]/parent is `always` and sits on 1
# of 480 records at the pin. This constant declares, for every collection
# whose records are not uniform, the record variants: a machine-evaluable
# predicate (`equals` / `gte` on one key - never on the absence of the key
# being explained, which both reviewers flagged as circular), the exact key
# set each variant carries, conditional keys whose PRESENCE is the value
# (SPEC 4.4's omit-rather-than-emit for negative booleans, promoted to a
# first-class slot at reviewer request), and axis keys present only when the
# axis is materialised. A record must match exactly one variant; a collection
# with no entry here is uniform, and the gate holds both claims. Serialised
# verbatim by --capabilities together with a derived per-path index
# (record_variant_path_index), so the record-in-hand reading and the
# collection-query planning - the two moments the reviewers split their
# preference across - are each served by a machine surface. Held by
# --self-check against the SPEC 13.3 table in both directions and by the
# gate against the pinned blob, a slice and the fixtures.
RECORD_VARIANTS = {
    "symbols": {
        # D12: the common set SHRANK to what a boundary stub carries - the
        # four keys that identify and locate a symbol. Everything analytic
        # moved into the full variants' carries, so the stub variant is
        # "common plus its discriminator" and a full record is "common plus
        # the analysis payload".
        "common_keys": ("end_line", "id", "kind", "start_line"),
        "variants": (
            {"name": "top-level", "when": {"path": "depth", "equals": 0},
             "carries": ("depth", "facts", "hash_body", "hash_full",
                         "hash_raw", "name", "parameters"),
             "conditional_keys": {"ordinal": {
                 "presence_means": "the identifier carries a "
                                   "position-dependent ordinal "
                                   "disambiguator (SPEC 5.2, PSS9007)",
                 "absence_means": "the name is unique in the file"}},
             "axis_keys": {}},
            {"name": "nested", "when": {"path": "depth", "gte": 1},
             "carries": ("depth", "facts", "hash_body", "hash_full",
                         "hash_raw", "name", "parameters", "parent"),
             "conditional_keys": {"ordinal": {
                 "presence_means": "the identifier carries a "
                                   "position-dependent ordinal "
                                   "disambiguator (SPEC 5.2, PSS9007)",
                 "absence_means": "the name is unique in the file"}},
             "axis_keys": {}},
            # D12: a boundary stub appears ONLY on a --scope slice
            # (SLICE_PROJECTION.boundary_stubs); a surveyed model never
            # emits one, which is why the exercised check reads the sliced
            # model in the checked set. Discriminated on `record`: a full
            # record carries no `record` key, so the depth predicates and
            # this one are mutually exclusive by construction.
            {"name": "stub", "when": {"path": "record", "equals": "stub"},
             "carries": ("record",), "conditional_keys": {},
             "axis_keys": {}},
        ),
    },
    "closures": {
        "common_keys": (),
        "variants": (
            {"name": "closure-row",
             "when": {"path": "record", "equals": "closure"},
             "carries": ("facts", "id", "record", "transitive_callee_count",
                         "transitive_caller_count"),
             "conditional_keys": {},
             "axis_keys": {"closure-sets": ("transitive_callees",
                                            "transitive_callers")}},
            {"name": "uncalled-fact",
             "when": {"path": "code", "equals": "PSS4003"},
             "carries": ("code", "id"),
             "conditional_keys": {"named_by_literal": {
                 "presence_means": "true - the function is named by a string "
                                   "literal somewhere in the file (SPEC 4.4)",
                 "absence_means": "false - the omit-rather-than-emit "
                                  "convention for negative booleans"}},
             "axis_keys": {}},
            {"name": "cycle-fact",
             "when": {"path": "code", "equals": "PSS4004"},
             "carries": ("code", "members"),
             "conditional_keys": {}, "axis_keys": {}},
        ),
    },
    "local_variables": {
        "common_keys": (),
        "variants": (
            {"name": "reference",
             "when": {"path": "record", "equals": "reference"},
             "carries": ("code", "id", "line", "name", "owner", "record",
                         "role"),
             "conditional_keys": {
                 "rhs": {
                     "presence_means": "role is write and the declaration has "
                                       "a supplying expression - carried "
                                       "verbatim (SPEC 12.8)",
                     "absence_means": "role is read, or the write has no "
                                      "supplying expression (SPEC 12.8's "
                                      "exclusions)"},
                 "rhs_span": {
                     "presence_means": "exactly when rhs is present: [start, "
                                       "end) byte offsets with text[start:end]"
                                       " == rhs, gate-held (SPEC 12.8)",
                     "absence_means": "exactly when rhs is absent"},
                 "in_expandable_string": {
                 "presence_means": "true - the site sits inside an "
                                   "expandable string",
                 "absence_means": "false"}},
             "axis_keys": {}},
            {"name": "aggregate",
             "when": {"path": "record", "equals": "aggregate"},
             "carries": ("automatic_refs", "local_declared", "local_refs",
                         "owner", "record", "unresolved_refs"),
             "conditional_keys": {}, "axis_keys": {}},
        ),
    },
    "script_variables": {
        "common_keys": (),
        "variants": (
            {"name": "reference",
             "when": {"path": "record", "equals": "reference"},
             "carries": ("code", "id", "line", "name", "owner", "qualifier",
                         "record", "role"),
             "conditional_keys": {
                 "rhs": {
                     "presence_means": "role is write and the declaration has "
                                       "a supplying expression - carried "
                                       "verbatim (SPEC 12.8)",
                     "absence_means": "role is read, or the write has no "
                                      "supplying expression (SPEC 12.8's "
                                      "exclusions)"},
                 "rhs_span": {
                     "presence_means": "exactly when rhs is present: [start, "
                                       "end) byte offsets with text[start:end]"
                                       " == rhs, gate-held (SPEC 12.8)",
                     "absence_means": "exactly when rhs is absent"},
                 "in_expandable_string": {
                 "presence_means": "true - the site sits inside an "
                                   "expandable string",
                 "absence_means": "false"}},
             "axis_keys": {}},
            {"name": "usage-map",
             "when": {"path": "record", "equals": "usage_map"},
             "carries": ("code", "id", "name", "reader_count", "readers",
                         "record", "writer_count", "writers"),
             "conditional_keys": {}, "axis_keys": {}},
        ),
    },
    "string_interpolation_references": {
        "common_keys": (),
        "variants": (
            {"name": "reference",
             "when": {"path": "record", "equals": "reference"},
             "carries": ("code", "id", "in_expandable_string", "line", "name",
                         "owner", "record", "role"),
             "conditional_keys": {"qualifier": {
                 "presence_means": "the interpolated reference carries a "
                                   "scope qualifier",
                 "absence_means": "the reference is unqualified"}},
             "axis_keys": {}},
        ),
    },
    "unresolved_named_commands": {
        "common_keys": (),
        "variants": (
            {"name": "site",
             "when": {"path": "record", "equals": "site"},
             "carries": ("arguments", "code", "line", "name", "owner",
                         "record", "span"),
             "conditional_keys": {}, "axis_keys": {}},
            {"name": "aggregate",
             "when": {"path": "record", "equals": "aggregate"},
             "carries": ("code", "name", "owners", "record", "sites"),
             "conditional_keys": {}, "axis_keys": {}},
        ),
    },
    # D12: limitations joined the declared set the moment PSS9002 records
    # gained `target` - one code carrying a key three others do not is
    # exactly a variant, and the alternative (a uniform collection with the
    # key silently sometimes-present) is the shape round 3's candidate-A
    # specimen demonstrated failing. Discriminated on `code`: every
    # limitations record carries exactly one, and the codes are disjoint by
    # construction (SPEC 4.8).
    "limitations": {
        "common_keys": ("code", "detail", "line", "owner"),
        "variants": (
            {"name": "unresolved-call-site",
             "when": {"path": "code", "equals": "PSS9002"},
             "carries": ("target",), "conditional_keys": {}, "axis_keys": {}},
            {"name": "untrackable-scope-write",
             "when": {"path": "code", "equals": "PSS9003"},
             "carries": (), "conditional_keys": {}, "axis_keys": {}},
            {"name": "unresolvable-read",
             "when": {"path": "code", "equals": "PSS9004"},
             "carries": (), "conditional_keys": {}, "axis_keys": {}},
            {"name": "ordinal-identifier",
             "when": {"path": "code", "equals": "PSS9007"},
             "carries": (), "conditional_keys": {}, "axis_keys": {}},
        ),
    },
}


def record_variant_path_index():
    """The per-path view DERIVED from RECORD_VARIANTS - candidate A's
    collection-query convenience generated from candidate B's record-local
    truth, so the two cannot disagree (the round-3 hybrid adjudication)."""
    index = {}
    for coll, cdecl in sorted(RECORD_VARIANTS.items()):
        keys = {}
        for v in cdecl["variants"]:
            for k in cdecl.get("common_keys", ()):
                keys.setdefault(k, {"present_on": [], "conditional_in": [],
                                    "axis": None})["present_on"].append(v["name"])
            for k in v["carries"]:
                keys.setdefault(k, {"present_on": [], "conditional_in": [],
                                    "axis": None})["present_on"].append(v["name"])
            for k in (v.get("conditional_keys") or {}):
                keys.setdefault(k, {"present_on": [], "conditional_in": [],
                                    "axis": None})["conditional_in"].append(v["name"])
            for axis, aks in (v.get("axis_keys") or {}).items():
                for k in aks:
                    e = keys.setdefault(k, {"present_on": [],
                                            "conditional_in": [], "axis": None})
                    e["present_on"].append(v["name"])
                    e["axis"] = axis
        for k, e in keys.items():
            index["/%s[]/%s" % (coll, k)] = e
    return index


# ---------------------------------------------------------------------------
# SPEC 5.8: how a caller joins the collections to each other.
#
# MODEL_SCHEMA says which key paths exist; it does not say which of them carry
# an identifier, which identifier space that is, or what a caller may join on.
# A consumer that cannot answer those three questions can read the model and
# cannot relate one collection to another, which is the gap SPEC 3.1 names as
# "the join key for each collection".
#
# These live in the code, not only in the SPEC, for the reason MODEL_SCHEMA
# does (ADR 0036): --capabilities serialises the declaration rather than
# restating it, so there is one copy of the fact.
# ---------------------------------------------------------------------------

# The reserved pseudo-owner (SPEC 10.6). It is a legal value wherever a symbol
# identifier is expected, and it is deliberately NOT a member of `symbols`:
# script level is a source position, not a definition.
SCRIPT_OWNER = "<script>"

# Anchored implicitly: the checker applies fullmatch, so a form is the whole
# identifier or it is not that form. The forms are disjoint by construction -
# every identifier matches exactly one - which is what lets a caller dispatch
# on the form without an ordering rule.
IDENTIFIER_FORMS = {
    "function": r"function/[^/#]+(?:/[^/#]+)*(?:#[0-9]+)?",
    "variable:automatic": r"variable:automatic/[^/]+",
    "variable:env": r"variable:env/[^/]+",
    "variable:local": r"variable:local/[^/#]+(?:/[^/#]+)*#[^/#]+",
    "variable:script": r"variable:script/[^/]+",
    "variable:unqualified": r"variable:unqualified/[^/]+",
}

# Per collection:
#   unique          - the field tuple that identifies a record, or None where
#                     records are not individually identified. `None` is a
#                     statement, not an omission: a collection carrying several
#                     record shapes (SPEC 11.1) has no single identifying key,
#                     and a caller must not invent one.
#   symbol_refs     - fields whose every value is a member of `symbols[].id`
#                     or the reserved SCRIPT_OWNER. These are the joins.
#   identifier_refs - fields carrying an identifier of some form (SPEC 5.2)
#                     that does NOT resolve into `symbols`, because `symbols`
#                     carries function definitions only. Separated from
#                     symbol_refs because a caller joining on one of these
#                     against `symbols` gets an empty result and no error.
COLLECTION_KEYS = {
    "closures": {
        "unique": None,
        "symbol_refs": ("id", "members", "transitive_callees",
                        "transitive_callers"),
        "identifier_refs": (),
    },
    "edges": {
        # Structural, not observed: the edge store is keyed by (from, to) and
        # `sites` counts the occurrences that fold into one record.
        "unique": ("from", "to"),
        "symbol_refs": ("from", "to"),
        "identifier_refs": (),
    },
    "limitations": {
        "unique": None,
        "symbol_refs": ("owner",),
        "identifier_refs": (),
    },
    "local_variables": {
        "unique": None,
        "symbol_refs": ("owner",),
        "identifier_refs": ("id",),
    },
    "script_variables": {
        "unique": None,
        "symbol_refs": ("owner", "readers", "writers"),
        "identifier_refs": ("id",),
    },
    "soft_references": {
        # `matches` resolves to a function OR to a script variable, so it is
        # not a symbol join even though most of its values happen to be one.
        "unique": None,
        "symbol_refs": ("owner",),
        "identifier_refs": ("matches",),
    },
    "string_interpolation_references": {
        "unique": None,
        "symbol_refs": ("owner",),
        "identifier_refs": ("id",),
    },
    "symbols": {
        "unique": ("id",),
        "symbol_refs": ("parent",),
        "identifier_refs": (),
    },
    "unresolved_named_commands": {
        "unique": None,
        "symbol_refs": ("owner", "owners"),
        "identifier_refs": (),
    },
}

COLLECTION_KEY_FIELDS = ("unique", "symbol_refs", "identifier_refs")


# ---------------------------------------------------------------------------
# SPEC 3.1: the capability descriptor.
#
# The descriptor SERIALISES the declarations above; it does not restate them.
# What it adds is the two things the constants cannot carry: what each exit
# code means, and which machine outputs this build actually produces.
# ---------------------------------------------------------------------------

# Held against the SPEC 9 table by --self-check, on code AND text: an exit code
# whose published meaning has drifted from the document is worse than one with
# no published meaning, because a caller branches on it.
EXIT_CODES = {
    "0": "The requested operation completed.",
    "2": "Usage error, unreadable input, unmet environment requirement, "
         "or internal error.",
}

# The subset of `--format` that is a serialisation rather than a summary
# (SPEC 6.3). Carried as a list so that an addition is an extension rather
# than a schema change.
MACHINE_FORMATS = ("json",)

# Every machine output SPEC 3.1 requires the descriptor to describe, with the
# status of each IN THIS BUILD.
#
# A descriptor that has drifted from the tool is worse than no descriptor
# (SPEC 3.1), and the drift a descriptor is most likely to carry is optimism:
# describing a shape the tool does not yet produce. Two of the four required
# outputs do not exist here. They are published with an explicit status and a
# reason rather than omitted, because omission is indistinguishable from an
# oversight - and the mark is not a promise, it is a claim test_pss.py checks
# against behaviour: `compare` must actually refuse, and an error under
# `--format json` must actually not be JSON. Implementing either without
# moving its mark turns the gate red.
# Which codes this build evaluates. `surveyed` reports a tally for each, and a
# code absent from that tally means "did not run" rather than "ran clean"
# (SPEC 6.4). Codes not listed here are therefore not silently reported as
# finding nothing - they are visibly missing, which is the point.
COMPARATOR_CODES = (
    "PSS6001", "PSS6002", "PSS6003",
    "PSS7001", "PSS7002", "PSS7003", "PSS7004", "PSS7005", "PSS7006",
    "PSS7007",
    "PSS8001", "PSS8002", "PSS8003", "PSS8004", "PSS8008",
)

# The three rules of SPEC 12.7. They presuppose that one model is a later
# state of the other, which the tool cannot verify and only the caller can
# assert - so they are emitted by `trace` and never by `compare` (SPEC 4.9).
# "An incomplete rename" is not a fact about two unrelated files.
SUCCESSION_CODES = ("PSS8005", "PSS8006", "PSS8007")

# SPEC 11.3 / 11.4: the classification vocabularies, each in ITS OWN table's
# row order - the two tables order their rows differently ((same, differs)
# is 11.3's second row and 11.4's third), so the row-key sequences are stated
# per table rather than shared, and the cell lookups are derived from the
# pairs so the descriptor and the comparator cannot disagree. One copy:
# `--capabilities` serialises these, because the intended caller holds no
# SPEC (SPEC 2.6) and a round-2 reviewer had to guess the enum from the
# value names (A4).
PSS7005_CLASSIFICATIONS = ("dependencies-unchanged", "downstream-changed",
                           "direct-only-change", "dependencies-changed")
_PSS7005_ROWS = ((True, True), (True, False), (False, True), (False, False))
PSS7006_CLASSIFICATIONS = ("unchanged", "local-change",
                           "dependency-only", "change-and-propagation")
_PSS7006_ROWS = ((True, True), (False, True), (True, False), (False, False))

_PSS7005_CELL = dict(zip(_PSS7005_ROWS, PSS7005_CLASSIFICATIONS))
_PSS7006_CELL = dict(zip(_PSS7006_ROWS, PSS7006_CLASSIFICATIONS))


MACHINE_OUTPUTS = {
    "model": {
        "status": "implemented",
        "emitted_by": "survey --format json, slice --format json",
        "shape": "model_schema, collection_keys, identifier_forms",
        "reason": None,
    },
    "cost_report": {
        "status": "implemented",
        "emitted_by": "survey --cost, and embedded in every model",
        "shape": "the /cost subtree of model_schema",
        "reason": None,
    },
    "delta_records": {
        "status": "implemented",
        "emitted_by": "compare --format json, trace --format json",
        "shape": {
            "top_level": ("delta_records", "surveyed", "examined_subjects",
                          "not_evaluated",
                          "direction", "source_a", "source_b", "excluded"),
            "top_level_conditional": ("source_path_differs",),
            "record": {
                "always": ("code", "subject", "subject_kind"),
                "conditional": ("equality", "detail"),
            },
            "equality_values": ("equal", "differs"),
            "classification_values": {
                "PSS7005": PSS7005_CLASSIFICATIONS,
                "PSS7006": PSS7006_CLASSIFICATIONS,
            },
            "directions": ("unrelated", "caller-asserted-succession"),
            "codes_evaluated": COMPARATOR_CODES,
            "codes_evaluated_by_trace_only": SUCCESSION_CODES,
        },
        "reason": None,
        "coverage": "a code absent from a run's `surveyed` tally did NOT "
                    "run, which is not the same as running and finding "
                    "nothing. `compare` evaluates the fifteen codes that "
                    "hold without a claim of succession; `trace` evaluates "
                    "those and the three of SPEC 12.7, which presuppose that "
                    "the caller has asserted one model is a later state of "
                    "the other. All eighteen are implemented (SPEC 6.4)",
    },
    "error_payload": {
        "status": "not-implemented",
        "emitted_by": "stderr, when --format json was requested",
        "shape": None,
        "reason": "every diagnostic in this build is plain text; the "
                  "structured category/rejected-value/vocabulary payload of "
                  "SPEC 3.1 is design intent, not behaviour",
    },
}

MACHINE_OUTPUT_STATUSES = ("implemented", "not-implemented")


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
        # Var-token start offsets that ARE declaration sites (SPEC 12.2):
        # param() entries, inline signature parameters, foreach loop variables.
        # The scan flips their role to "write" without touching the assignment
        # counter, whose definition stays "assignment operators + parameter
        # defaults" (Appendix B differential).
        self.decl_write_offsets = set()
        # SPEC 12.8 (D13): var-token offset -> the foreach `in` expression's
        # byte span, recorded by _record_foreach and consumed when the loop
        # variable's write site is noted.
        self.foreach_rhs = {}
        # Script-owner unqualified usage contributions, applied AFTER
        # classification so the usage map does not depend on document order
        # (SPEC 12.3). Before this arc a script-side write classified while the
        # map was still empty was dropped, and only the later reads survived -
        # the mechanism behind PSS8007's seventeen-record noise.
        self.script_usage_events = []

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
            fid = self.func_ids[id(f)]
            for e in entries:
                self.decl_write_offsets.add(e.pop("offset"))
                self._decl_add(fid, e["name"])
            self.params_by_func[id(f)] = entries
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
                    self.decl_write_offsets.add(e["offset"])
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
                assignment = False
                if nxt is not None and nxt.kind == 'op' and not member_name:
                    if nxt.text == '=' or nxt.text == '??=' or nxt.text in _ASSIGN_OPS:
                        role = "write"
                        assignment = True
                    elif nxt.text in ('.', '[', '::'):
                        # A member or index left-hand side REFERENCES the
                        # variable; it never declares anything (SPEC 12.2).
                        role = "read"
                # A param() entry, inline signature parameter or foreach loop
                # variable is a declaration site (SPEC 12.2): its role is
                # "write" whether or not an assignment operator follows. The
                # counter below stays tied to the operator, because
                # `counters.assignments` is defined as assignment statements
                # plus parameter defaults, and the differential holds it there.
                if t.start in self.decl_write_offsets:
                    role = "write"
                rhs_span = None
                if assignment:
                    # SPEC 12.8: the supplying expression begins after the
                    # assignment operator (sig position k + 1). Inside a
                    # param() block (a declaration-listed site) the entry's
                    # own separator ends the default expression - a `,` at
                    # statement level is an array literal, a `,` between
                    # parameters is not.
                    rhs_span = self._rhs_span_from(
                        k + 1, stop_comma=t.start in self.decl_write_offsets)
                elif role == "write":
                    rhs_span = self.foreach_rhs.get(t.start)
                self._note_variable(t.start, t.text, in_string=False,
                                    role=role, rhs_span=rhs_span)
                if assignment:
                    self.counters["assignments"] += 1

            if t.kind == 'word':
                low = t.text.lower()
                if cmd_pos and low == 'foreach':
                    self._record_foreach(k)
                if low in ('set-variable', 'new-variable'):
                    self._record_set_variable(k)
                if low in _OUTVAR_PARAMS and nxt is not None:
                    # `-OutVariable ov` declares $ov in the calling scope
                    # (SPEC 12.2). `+ov` is the append form of the same name;
                    # the sign tokenizes as its own operator, so the name is
                    # the token after it.
                    nm = nxt
                    if nm.kind == 'op' and nm.text == '+' and k + 2 < len(sig):
                        nm = toks[sig[k + 2]]
                    value = self._literal_name(nm)
                    if value:
                        value = value.lstrip('+')
                    if value:
                        self._decl_add(self._owner_id_fast(nm.start), value)
                        self._synthesize_decl_site(nm.start, value)

            if t.kind == 'op' and t.text in ('&', '.') and nxt is not None and cmd_pos:
                if nxt.kind == 'var' or (nxt.kind == 'op' and nxt.text == '('):
                    self.counters["commands_dynamic"] += 1
                    ts, te = _dynamic_target(toks, sig[k + 1])
                    self.limitations.append({
                        "code": "PSS9002",
                        "owner": self._owner_id_fast(t.start),
                        "line": self.line_of(t.start),
                        "detail": "invocation through '%s' with a non-literal target" % t.text,
                        # SPEC 4.8 (D12): the name expression, verbatim, so a
                        # consumer can JOIN it against the variable collections
                        # instead of returning to the source - the round-3
                        # rename pre-flight that fell back to grep.
                        "target": self.text[ts:te],
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
                arguments, span = _command_arguments(
                    self.text, toks, sig, k, t)
                self.unresolved_named_commands.append({
                    "code": "PSS2009", "name": t.text,
                    "owner": self._owner_id_fast(t.start),
                    "line": self.line_of(t.start), "offset": t.start,
                    "arguments": arguments, "span": span,
                })
                continue
            # The edge source may be <script>: a function called only from top
            # level is not an orphan, and excluding script-level edges makes 12
            # such functions falsely report PSS4003 (SPEC 4.2, revised).
            src = self._owner_id_fast(t.start)
            dst = self.func_ids[id(targets[0])]
            rec = self.edges.get((src, dst))
            if rec is None:
                self.edges[(src, dst)] = {"from": src, "to": dst, "sites": 1,
                                          "lines": [self.line_of(t.start)]}
            else:
                rec["sites"] += 1
                rec["lines"].append(self.line_of(t.start))

    def _rhs_span_from(self, k_op, stop_comma=False):
        """SPEC 12.8 (D13): the supplying expression's [start, end) byte span.

        From the first significant token after the assignment operator to the
        end of the pipeline statement: a `;`, a non-continuation newline, or
        the enclosing group's closer. A newline continues the statement when
        the token before it is an operator that cannot end one (a pipe, a
        comma, a binary operator, an opening group - never a closer), or when
        the RHS has not started yet. Grouped regions are crossed whole, so an
        inner `;` or newline never ends the statement. Backtick continuations
        never surface here: the lexer folds the escaped newline into a `bt`
        token, which `significant` drops. `end` advances only on significant
        tokens, so a trailing comment is never part of the expression. The
        span is the verbatim contract: the record's `rhs` is exactly
        text[start:end], and the gate holds that equality over every write.
        """
        toks, sig = self.toks, self.sig
        j = k_op + 1
        start = None
        end = None
        while j < len(sig):
            t = toks[sig[j]]
            if stop_comma and t.kind == 'op' and t.text == ',':
                break               # a param() entry ends at its separator
            if t.kind == 'nl':
                if end is None:
                    j += 1          # the RHS starts on the next line
                    continue
                prev = toks[sig[j - 1]]
                if prev.kind == 'op' and prev.text not in (')', '}', ']'):
                    j += 1          # continuation: `|`, `,`, `+`, `(` ...
                    continue
                break
            if t.kind == 'op':
                if t.text == ';':
                    break
                if t.text in (')', '}', ']'):
                    break           # the enclosing group's closer
                if t.text in ('(', '{', '['):
                    depth = 1
                    if start is None:
                        start = t.start
                    end = t.end
                    j += 1
                    while j < len(sig) and depth:
                        tt = toks[sig[j]]
                        if tt.kind == 'op':
                            if tt.text in ('(', '{', '['):
                                depth += 1
                            elif tt.text in (')', '}', ']'):
                                depth -= 1
                        if tt.kind != 'nl':
                            end = tt.end
                        j += 1
                    continue
            if start is None:
                start = t.start
            end = t.end
            j += 1
        if start is None or end is None or end <= start:
            return None
        return (start, end)

    def _record_foreach(self, k):
        toks, sig = self.toks, self.sig
        if k + 2 < len(sig) and toks[sig[k + 1]].kind == 'op' \
                and toks[sig[k + 1]].text == '(' and toks[sig[k + 2]].kind == 'var':
            v = toks[sig[k + 2]]
            _, name, _ = parse_var_token(v.text)
            self._decl_add(self._owner_id_fast(v.start), name)
            self.decl_write_offsets.add(v.start)
            # SPEC 12.8: the `in` expression supplies the loop variable's
            # value - it is the declaration's rhs. Scanned to the '(' group's
            # own closer via the same walk as an assignment rhs; the depth
            # starts inside the group, so the closer ends the span.
            if k + 4 < len(sig) and toks[sig[k + 3]].kind == 'word' \
                    and toks[sig[k + 3]].text.lower() == 'in':
                span = self._rhs_span_from(k + 3)
                if span:
                    self.foreach_rhs[v.start] = span

    def _literal_name(self, tok):
        """The variable name a `-Name`/`-OutVariable` value token declares, or
        None when the token is not a literal (SPEC 12.2 requires a literal: an
        expandable string carrying a variable or subexpression names nothing
        this tool can resolve statically)."""
        if tok.kind == 'word':
            return tok.text
        if tok.kind in ('str', 'estr'):
            if tok.kind == 'estr' and (expandable_var_sites(tok)
                                       or subexpression_spans(tok)):
                return None
            return string_value(tok)
        return None

    def _synthesize_decl_site(self, offset, name):
        """A declaration whose name is a string literal, not a var token
        (`Set-Variable -Name x`, `-OutVariable x`), still has a site: the name
        literal's own position. The synthesised site flows through the same
        classification as every var token, so it lands as PSS2002/PSS2006 with
        role "write" - but it does NOT touch `counters.variable_refs`, which
        counts variable tokens and this is not one (SPEC 12.2)."""
        low = name.lower()
        if low in AUTOMATIC_VARIABLES:
            return
        self.var_sites.append({
            "offset": offset, "name": name, "qualifier": None,
            "owner": self._owner_id_fast(offset), "role": "write",
            "in_string": False, "splatted": False,
        })

    def _record_set_variable(self, k):
        toks, sig = self.toks, self.sig
        for j in range(k + 1, min(k + 12, len(sig))):
            t = toks[sig[j]]
            if t.kind == 'word' and t.text.lower() == '-name':
                if j + 1 < len(sig):
                    nm = toks[sig[j + 1]]
                    value = self._literal_name(nm)
                    if value:
                        self._decl_add(self._owner_id_fast(nm.start), value)
                        self._synthesize_decl_site(nm.start, value)
                # D12: scanning CONTINUES past -Name. Returning here made
                # PSS9003 depend on parameter order - SPEC 4.8 claims a
                # -Scope write is reported, and `-Name X -Value 1 -Scope 1`,
                # the common order, was silently missed. The D10 -OutVariable
                # lesson in miniature: the SPEC claimed, the implementation
                # partially delivered, and the gap surfaced only when a
                # fixture exercised the claim.
                continue
            if t.kind == 'word' and t.text.lower() == '-scope':
                self.limitations.append({
                    "code": "PSS9003",
                    "owner": self._owner_id_fast(t.start),
                    "line": self.line_of(t.start),
                    "detail": "parent-scope write via -Scope cannot be tracked statically",
                })
            if t.kind == 'nl':
                return

    def _note_variable(self, offset, vtext, in_string, role, rhs_span=None):
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
            "splatted": splatted, "rhs_span": rhs_span,
        })

    def _classify_variables(self):
        """Assign every reference to exactly one class (SPEC 12.6).

        Check order is normative: qualifier, then automatic, then declaration.
        """
        # Script-scope name membership is collected in full BEFORE any site is
        # classified, so whether a function-side read is admitted to the usage
        # map cannot depend on where in the file the script-side site sits
        # (SPEC 12.3). This is the same membership the classification loop used
        # to build one site at a time.
        for s in self.var_sites:
            if s["qualifier"] is None and s["owner"] == "<script>" \
                    and s["name"].lower() not in AUTOMATIC_VARIABLES:
                self.script_decl_names.setdefault(s["name"].lower(), s["name"])
        for s in self.var_sites:
            name, low = s["name"], s["name"].lower()
            owner, role, offset = s["owner"], s["role"], s["offset"]
            line = self.line_of(offset)
            base = {
                "record": "reference", "name": name, "owner": owner,
                "line": line, "offset": offset, "role": role,
                "in_expandable_string": s["in_string"],
            }
            # SPEC 12.8 (D13): a write carries its supplying expression,
            # verbatim, plus the byte span that IS the verbatim contract -
            # text[a:b] == rhs, held by the gate over every write. Flows
            # through `base` so every write-classified record downstream
            # (PSS2002, PSS2004-write, PSS2005-write, PSS2006) carries it;
            # reads and writes with no supplying expression (SPEC 12.8's
            # exclusions) carry neither key.
            if role == "write" and s.get("rhs_span"):
                a, b = s["rhs_span"]
                base["rhs"] = self.text[a:b]
                base["rhs_span"] = [a, b]
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
                # Deferred to `_build_usage_map`: admitting this site now would
                # make the writer set depend on document order - a script-side
                # write classified while the map is still empty was dropped,
                # which is what put seventeen perfectly-declared parameters
                # into PSS8007 (SPEC 12.3, 12.7 rule (c)).
                self.script_usage_events.append((low, name, owner, role))
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
        # Script-owner unqualified contributions, deferred from classification
        # so admission is evaluated against the COMPLETE population rather than
        # the part of it that happened to classify first (SPEC 12.3). The
        # admission rule itself is unchanged: a script-owner site joins only a
        # name admitted by a `$script:` qualifier somewhere or by a
        # cross-boundary read; it never creates an entry for a name no
        # function touches.
        for low, name, owner, role in self.script_usage_events:
            if low in self.usage or low in self.script_qualified_names:
                self._usage_add(low, name, owner, role)
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
                 "owner": r["owner"], "line": r["line"], "offset": r["offset"],
                 # D12: the argument itemisation and the [start, end) byte
                 # span - the facts a round-3 destructive-invocation audit
                 # had to return to the source for (SPEC 4.2).
                 "arguments": r["arguments"], "span": r["span"]}
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
            # SPEC 5.9 [F2]: `lines` is every call site, ascending. Sites are
            # collected in scan order, and a site inside a `$( ... )`
            # subexpression is scanned after the top-level stream, so the
            # ascending order is established here, not assumed. `line` -
            # normatively lines[0], a duplicate by construction - is RETIRED
            # at the D12 arc (SPEC 5.9): the "3" consumers that read it were
            # reading a copy, and a copy of a fact is the shape this SPEC
            # spends 13.2 rows fighting.
            e["lines"].sort()

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
    # SPEC 6.2 (D12): a boundary stub is a reference marker, not a function
    # definition - the symbol rows read FULL records only, and the stub
    # count gets its own row, printed only when stubs exist. The renderer
    # crashed on the first stubbed slice (s["facts"] on a record that
    # carries none) precisely because no rule had been stated.
    full_syms = [s for s in model["symbols"] if s.get("record") != "stub"]
    stub_count = len(model["symbols"]) - len(full_syms)
    out.append("functions             : %d" % len(full_syms))
    if stub_count:
        out.append("boundary stubs        : %d  (slice boundary, SPEC 5.7)"
                   % stub_count)
    out.append("nested definitions    : %d" % sum(
        1 for s in full_syms if "PSS1004" in s["facts"]))
    out.append("duplicate names       : %d" % sum(
        1 for s in full_syms if "PSS1005" in s["facts"]))
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
def _spec_cell(cell):
    """Parse a SPEC 5.8 table cell holding a backticked field list.

    An em dash is the written form of "no fields", and is distinguished from an
    empty cell so that a row left blank by accident does not read as a
    deliberate declaration of nothing.
    """
    cell = cell.strip()
    if cell == "\u2014":
        return ()
    return tuple(part.strip().strip("`") for part in cell.split(",")
                 if part.strip())


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

    # Identifier forms and collection join keys (SPEC 5.8), in both
    # directions, exactly as the catalogue and the axis vocabulary above. The
    # descriptor of SPEC 3.1 serialises these constants, so a drift here would
    # be published to callers as fact.
    kstart = spec.find("### 5.8 Identifier forms and collection join keys")
    kend = spec.find("## 6. Output formats")
    fstart_5_8 = spec.find("#### Identifier forms", kstart) if kstart >= 0 else -1
    cstart_5_8 = spec.find("#### Collection join keys", kstart) if kstart >= 0 else -1
    if kstart < 0 or kend < 0 or fstart_5_8 < 0 or cstart_5_8 < 0 or not (
            kstart < fstart_5_8 < cstart_5_8 < kend):
        print("  FAIL: could not locate SPEC section 5.8 and its two tables")
        rc = EXIT_ERROR
    else:
        forms_section = spec[fstart_5_8:cstart_5_8]
        spec_forms = dict(re.findall(r'^\| `([a-z:]+)` \| `(.+?)` \|$',
                                     forms_section, re.M))
        form_missing_in_code = sorted(set(spec_forms) - set(IDENTIFIER_FORMS))
        form_missing_in_spec = sorted(set(IDENTIFIER_FORMS) - set(spec_forms))
        pattern_disagrees = sorted(
            k for k in set(spec_forms) & set(IDENTIFIER_FORMS)
            if spec_forms[k] != IDENTIFIER_FORMS[k])
        if form_missing_in_code:
            print("  FAIL: identifier form in SPEC.md 5.8 but not compiled "
                  "into pss.py: %s" % ", ".join(form_missing_in_code))
            rc = EXIT_ERROR
        if form_missing_in_spec:
            print("  FAIL: identifier form compiled into pss.py but absent "
                  "from SPEC.md 5.8: %s" % ", ".join(form_missing_in_spec))
            rc = EXIT_ERROR
        if pattern_disagrees:
            # The pattern IS the form. Agreeing on the name while disagreeing
            # on what it matches is the drift a descriptor makes dangerous.
            print("  FAIL: identifier form declared with a different pattern "
                  "in pss.py and SPEC.md 5.8: %s"
                  % ", ".join("%s (%s vs %s)"
                              % (k, IDENTIFIER_FORMS[k], spec_forms[k])
                              for k in pattern_disagrees))
            rc = EXIT_ERROR
        if not (form_missing_in_code or form_missing_in_spec
                or pattern_disagrees):
            print("  ident    : %d forms in IDENTIFIER_FORMS, %d in SPEC.md "
                  "section 5.8, agree on name and pattern"
                  % (len(IDENTIFIER_FORMS), len(spec_forms)))

        keys_section = spec[cstart_5_8:kend]
        spec_keys = {}
        for row in re.findall(r'^\| `([a-z_]+)` \| (.+?) \| (.+?) \| (.+?) \|$',
                              keys_section, re.M):
            name, uniq, syms, idents = row
            spec_keys[name] = {
                "unique": _spec_cell(uniq) or None,
                "symbol_refs": _spec_cell(syms),
                "identifier_refs": _spec_cell(idents),
            }
        code_keys = {c: {f: (tuple(v[f]) if v[f] else (None if f == "unique"
                                                       else ()))
                         for f in COLLECTION_KEY_FIELDS}
                     for c, v in COLLECTION_KEYS.items()}
        coll_missing_in_code = sorted(set(spec_keys) - set(code_keys))
        coll_missing_in_spec = sorted(set(code_keys) - set(spec_keys))
        cell_disagrees = sorted(
            "%s.%s" % (c, f)
            for c in set(spec_keys) & set(code_keys)
            for f in COLLECTION_KEY_FIELDS
            if spec_keys[c][f] != code_keys[c][f])
        if coll_missing_in_code:
            print("  FAIL: collection in SPEC.md 5.8 but not declared in "
                  "pss.py: %s" % ", ".join(coll_missing_in_code))
            rc = EXIT_ERROR
        if coll_missing_in_spec:
            print("  FAIL: collection declared in pss.py but absent from "
                  "SPEC.md 5.8: %s" % ", ".join(coll_missing_in_spec))
            rc = EXIT_ERROR
        if cell_disagrees:
            print("  FAIL: join-key declaration differs between pss.py and "
                  "SPEC.md 5.8: %s" % ", ".join(cell_disagrees))
            rc = EXIT_ERROR
        if not (coll_missing_in_code or coll_missing_in_spec or cell_disagrees):
            print("  joins    : %d collections in COLLECTION_KEYS, %d in "
                  "SPEC.md section 5.8, agree on every key field"
                  % (len(code_keys), len(spec_keys)))

    # Exit-code meanings (SPEC 9). The descriptor publishes these and a caller
    # branches on them, so text drift here is not cosmetic.
    estart = spec.find("## 9. Exit codes")
    eend = spec.find("## 10. Hashing and normalisation")
    if estart < 0 or eend < 0 or eend <= estart:
        print("  FAIL: could not locate SPEC section 9")
        rc = EXIT_ERROR
    else:
        spec_exits = dict(re.findall(r'^\| `(\d+)` \| (.+?) \|$',
                                     spec[estart:eend], re.M))
        exit_missing_in_code = sorted(set(spec_exits) - set(EXIT_CODES))
        exit_missing_in_spec = sorted(set(EXIT_CODES) - set(spec_exits))
        text_disagrees = sorted(k for k in set(spec_exits) & set(EXIT_CODES)
                                if spec_exits[k] != EXIT_CODES[k])
        if exit_missing_in_code:
            print("  FAIL: exit code in SPEC.md 9 but not compiled into "
                  "pss.py: %s" % ", ".join(exit_missing_in_code))
            rc = EXIT_ERROR
        if exit_missing_in_spec:
            print("  FAIL: exit code compiled into pss.py but absent from "
                  "SPEC.md 9: %s" % ", ".join(exit_missing_in_spec))
            rc = EXIT_ERROR
        if text_disagrees:
            print("  FAIL: exit code described differently in pss.py and "
                  "SPEC.md 9: %s" % ", ".join(text_disagrees))
            rc = EXIT_ERROR
        if not (exit_missing_in_code or exit_missing_in_spec
                or text_disagrees):
            print("  exits    : %d codes in EXIT_CODES, %d in SPEC.md "
                  "section 9, agree on code and meaning" % (len(EXIT_CODES),
                                                            len(spec_exits)))

    sstart = spec.find("### 13.3 The declared model schema")
    send = spec.find("## 14. Test-data acquisition")
    if sstart < 0 or send < 0 or send <= sstart:
        print("  FAIL: could not locate SPEC section 13.3")
        rc = EXIT_ERROR
    else:
        ssection = spec[sstart:send]
        spec_schema = dict(re.findall(r'^\| `(/[^`]+)` \| (always|axis|optional) \|$',
                                      ssection, re.M))
        path_missing_in_code = sorted(set(spec_schema) - set(MODEL_SCHEMA))
        path_missing_in_spec = sorted(set(MODEL_SCHEMA) - set(spec_schema))
        kind_disagrees = sorted(k for k in set(spec_schema) & set(MODEL_SCHEMA)
                                if spec_schema[k] != MODEL_SCHEMA[k])
        if path_missing_in_code:
            print("  FAIL: key path in SPEC.md 13.3 but not declared in pss.py: %s"
                  % ", ".join(path_missing_in_code))
            rc = EXIT_ERROR
        if path_missing_in_spec:
            print("  FAIL: key path declared in pss.py but absent from SPEC.md 13.3: %s"
                  % ", ".join(path_missing_in_spec))
            rc = EXIT_ERROR
        if kind_disagrees:
            # A kind is not decoration: "optional" is the only thing standing
            # between a data-dependent field and a silent shape change, so a
            # path present in both with the wrong kind is a drift, not a
            # cosmetic difference.
            print("  FAIL: key path declared with a different kind in pss.py and "
                  "SPEC.md 13.3: %s"
                  % ", ".join("%s (%s vs %s)" % (k, MODEL_SCHEMA[k], spec_schema[k])
                              for k in kind_disagrees))
            rc = EXIT_ERROR
        if not path_missing_in_code and not path_missing_in_spec and not kind_disagrees:
            print("  schema   : %d paths in MODEL_SCHEMA, %d in SPEC.md section 13.3, "
                  "agree on path and kind"
                  % (len(MODEL_SCHEMA), len(spec_schema)))

        # Value nullability (the SPEC 13.3 subsection). The machine fact is
        # the path set; the "null states" prose is documentation and lives
        # once, in the code, serialised via --capabilities. A nullable path
        # must also be a declared key path - a mark on a path the schema does
        # not carry marks nothing.
        nstart = ssection.find("#### Value nullability")
        if nstart < 0:
            print("  FAIL: could not locate the SPEC 13.3 Value nullability "
                  "subsection")
            rc = EXIT_ERROR
        else:
            nsection = ssection[nstart:]
            spec_nullable = set(re.findall(r'^\| `(/[^`]+)` \|', nsection, re.M))
            null_missing_in_code = sorted(spec_nullable - set(NULLABLE_PATHS))
            null_missing_in_spec = sorted(set(NULLABLE_PATHS) - spec_nullable)
            undeclared = sorted(set(NULLABLE_PATHS) - set(MODEL_SCHEMA))
            if null_missing_in_code:
                print("  FAIL: nullable in SPEC.md 13.3 but not declared in "
                      "pss.py: %s" % ", ".join(null_missing_in_code))
                rc = EXIT_ERROR
            if null_missing_in_spec:
                print("  FAIL: nullable declared in pss.py but absent from "
                      "SPEC.md 13.3: %s" % ", ".join(null_missing_in_spec))
                rc = EXIT_ERROR
            if undeclared:
                print("  FAIL: nullable path is not a declared key path: %s"
                      % ", ".join(undeclared))
                rc = EXIT_ERROR
            if not (null_missing_in_code or null_missing_in_spec or undeclared):
                print("  nullable : %d paths, SPEC.md 13.3 and pss.py agree; "
                      "all are declared key paths" % len(NULLABLE_PATHS))

        # Per-record presence (the SPEC 13.3 subsection, round-3 B1). The
        # machine fact compared here is the variant signature - collection,
        # variant name, predicate, carried keys, conditional keys. The
        # observed column is data-dependent and is held by the gate against
        # the pinned blob, not here: --self-check runs without any input.
        vstart = ssection.find("#### Per-record presence")
        if vstart < 0:
            print("  FAIL: could not locate the SPEC 13.3 Per-record "
                  "presence subsection")
            rc = EXIT_ERROR
        else:
            vsection = ssection[vstart:]
            def _norm(cell):
                return " ".join(cell.replace("`", "").split())
            spec_rows = {}
            # The observed cell is data-dependent and may be prose for a
            # variant the pin does not produce (D12: two limitations codes,
            # and the slice-only stub); the signature comparison never reads
            # it, so the row match accepts any final cell. The GATE's
            # stated-vs-measured comparison still requires pure digits, so a
            # prose cell is exactly the mark of a variant the pin cannot
            # measure - which the exercised check then demands elsewhere.
            for m2 in re.finditer(
                    r"^\| `([a-z_]+)` \| `([a-z-]+)` \| (.+?) \| (.+?) \| "
                    r"(.+?) \| .+? \|$", vsection, re.M):
                spec_rows[(m2.group(1), m2.group(2))] = (
                    _norm(m2.group(3)), _norm(m2.group(4)), _norm(m2.group(5)))
            code_rows = {}
            for coll, cdecl in sorted(RECORD_VARIANTS.items()):
                for v in cdecl["variants"]:
                    w = v["when"]
                    when = "%s == %s" % (w["path"], w["equals"]) \
                        if "equals" in w else "%s >= %s" % (w["path"], w["gte"])
                    carries = " ".join(v["carries"]) if v["carries"] \
                        else "(common only)"
                    cond = " ".join(sorted(v.get("conditional_keys") or {})) \
                        or "\u2014"
                    code_rows[(coll, v["name"])] = (_norm(when),
                                                    _norm(carries),
                                                    _norm(cond))
            v_missing_in_spec = sorted(set(code_rows) - set(spec_rows))
            v_missing_in_code = sorted(set(spec_rows) - set(code_rows))
            v_disagrees = sorted(k for k in set(code_rows) & set(spec_rows)
                                 if code_rows[k] != spec_rows[k])
            if v_missing_in_spec:
                print("  FAIL: record variant declared in pss.py but absent "
                      "from SPEC.md 13.3: %s"
                      % ", ".join("%s/%s" % k for k in v_missing_in_spec))
                rc = EXIT_ERROR
            if v_missing_in_code:
                print("  FAIL: record variant in SPEC.md 13.3 but not "
                      "declared in pss.py: %s"
                      % ", ".join("%s/%s" % k for k in v_missing_in_code))
                rc = EXIT_ERROR
            if v_disagrees:
                print("  FAIL: record variant signature differs between "
                      "pss.py and SPEC.md 13.3: %s"
                      % ", ".join("%s/%s (%r vs %r)"
                                  % (k + (code_rows[k], spec_rows[k]))
                                  for k in v_disagrees))
                rc = EXIT_ERROR
            if not (v_missing_in_spec or v_missing_in_code or v_disagrees):
                print("  variants : %d record variants over %d collections, "
                      "SPEC.md 13.3 and pss.py agree"
                      % (len(code_rows), len(RECORD_VARIANTS)))

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


def _referenced_symbol_ids(model):
    """Every symbol identifier the model's scoped collections reference -
    read from ``COLLECTION_KEYS[...].symbol_refs``, the D11 declaration of
    exactly the fields whose every value joins into ``symbols[].id`` (or is
    the reserved script owner). Declaration-driven on purpose: a hand-rolled
    field list here collected variable-record ``id`` values on first
    measurement - identifiers of a different form (SPEC 5.2) that never
    resolve into ``symbols`` - and the declaration already separates the two
    as ``symbol_refs`` vs ``identifier_refs``. ``limitations`` is excluded
    the same way the scope filter excludes it: kept in full as whole-file
    context (SPEC 5.7), its owners are not the slice's references.
    """
    ids = set()
    for key in _SCOPED_COLLECTIONS:
        refs = COLLECTION_KEYS.get(key, {}).get("symbol_refs", ())
        for r in model.get(key, ()) or ():
            for f in refs:
                v = r.get(f)
                if isinstance(v, str):
                    ids.add(v)
                elif isinstance(v, (list, tuple)):
                    ids.update(x for x in v if isinstance(x, str))
    ids.discard(SCRIPT_OWNER)
    return ids


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


# SPEC 5.7 / round-3 B2: the projection contract, DECLARED. The rules below
# are what slice_model has always done; what was missing was any statement of
# them, which sent a round-3 reviewer reverse-engineering slice/parent pairs
# to learn that `limitations` is source-global and an unresolved-command
# aggregate keeps source-wide figures. One copy: `scoped_collections` is the
# implementation's own tuple, and --capabilities serialises this constant.
SLICE_PROJECTION = {
    "rule": "membership-filter",
    "semantics": "a --scope slice keeps or drops WHOLE records by one "
                 "membership rule (the scope identifier appearing in any "
                 "membership field) and never rewrites a kept record, so "
                 "counts and lists inside a kept record remain facts about "
                 "the whole source - an unresolved-command aggregate kept "
                 "because its owners include the scope still states "
                 "source-wide sites and owners (SPEC 5.7)",
    "membership_fields": ("id", "from", "to", "owner", "matches",
                          "members", "owners"),
    "scoped_collections": tuple(_SCOPED_COLLECTIONS),
    "kept_in_full": {
        "limitations": "describes what could NOT be determined; filtering "
                       "it would misrepresent the projection's own coverage",
        "counters": "whole-survey metadata, never per-symbol",
        "source": "whole-survey metadata, never per-symbol",
    },
    "recomputed": {
        "cost": "describes the slice itself; an axis the slice no longer "
                "carries prices as null (SPEC 5.6), a kept axis as 0",
        "materialization": "declares the scope and the axis set",
    },
    # D12: the ONE stated exception to "keeps or drops whole records".
    "boundary_stubs": {
        "rule": "additive-stub",
        "semantics": "after scoping, every symbol identifier the kept "
                     "records reference through a membership field and the "
                     "slice does not contain is re-introduced as a stub "
                     "symbols record - record='stub' plus the four common "
                     "keys (id, kind, start_line, end_line), copied "
                     "verbatim from the input model. Additive only: no "
                     "kept record is rewritten, no stub carries analysis "
                     "payload, and an identifier without a symbols record "
                     "in the input (<script>) is not stubbed. Closes the "
                     "round-3 finding of 33 edge endpoints resolving to "
                     "nothing inside a function slice (SPEC 5.7)",
    },
}


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
        # D12 boundary stubs (SPEC 5.7, SLICE_PROJECTION.boundary_stubs):
        # re-introduce every referenced-but-absent symbol as a stub, sourced
        # from the INPUT model - including an input's own stubs, so slicing
        # a slice cannot dangle what the first slice resolved.
        by_id = {s["id"]: s for s in model.get("symbols", ())}
        have = {s["id"] for s in out.get("symbols", ())}
        boundary = _referenced_symbol_ids(out) - have
        stubs = [{"record": "stub", "id": i, "kind": by_id[i]["kind"],
                  "start_line": by_id[i]["start_line"],
                  "end_line": by_id[i]["end_line"]}
                 for i in sorted(boundary) if i in by_id]
        if stubs:
            out["symbols"] = sorted(list(out.get("symbols", ())) + stubs,
                                    key=lambda r: r["id"])

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

    mv = model.get("model_version")
    if mv != MODEL_VERSION:
        sys.stderr.write(
            "pss.py: slice: PSS9005 - the model carries model_version %s and "
            "this build slices under model_version %s. A slice re-emits the "
            "document under this build's contract (the boundary stubs are a "
            "model_version-4 shape), so slicing across the boundary would "
            "produce a document whose stated version and actual shape "
            "disagree. Re-survey the source with this build, or slice with "
            "the build that produced the model. No partial slice is "
            "produced.\n" % (mv, MODEL_VERSION))
        return EXIT_ERROR

    current_axes = frozenset(model.get("materialization", {}).get("axes", []))
    requested_axes = None
    if args.axes is not None:
        if args.axes.strip() in AXES_ALIAS:
            # The alias on slice means "every axis the INPUT has", not the
            # global vocabulary (survey's reading) - a slice never adds
            # material. Both readings are declared in AXES_ALIAS (SPEC 3.1).
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


# --------------------------------------------------------------------------
# Layer 3: the comparator (SPEC 4.5-4.9, 5.5, 5.7, 6.4)
# --------------------------------------------------------------------------
#
# One comparator, two verbs. `compare` claims no relation between its inputs;
# `trace` carries the caller's assertion that B is a later state of A. The
# assertion is unverifiable, so the tool requires it to be stated rather than
# inferring it - which is why these are verbs and not a defaulted flag.
#
# Only three codes need the assertion (PSS8005/8006/8007, SPEC 4.9). The other
# fifteen hold for any two models, so `trace` is this comparator plus one rule
# layer, and no comparison logic is written twice.

def _functions(model):
    return {s["id"]: s for s in model.get("symbols", ())
            if s.get("kind") == "function"}


def _usage_maps(model):
    """The usage-map records only.

    `script_variables` mixes two grains: one record per reference site, and one
    usage map per variable. PSS7007 is specified over the map, so taking the
    whole collection would compare reference sites against usage maps.
    """
    return {v["id"]: v for v in model.get("script_variables", ())
            if v.get("record") == "usage_map"}


def _usage_state(model, vid):
    """SPEC 6.4 / round-3 B4: one model's usage state for a script variable -
    writer and reader identities WITH the site lines that model's own
    reference records retain. This is exactly the join both round-3
    reviewers performed by hand against the raw models before acting on a
    PSS7007/PSS8006/PSS8007 record; the delta writer holds both models at
    emission time, so the state is transcribed rather than reconstructed.
    Facts only: `writer_count` counts identities with retained reference
    sites in THIS model, and an empty `lines` list would mean an identity
    the usage map names without a retained site - retention, not verdict."""
    sites = {"read": {}, "write": {}}
    for r in model.get("script_variables", ()):
        if r.get("record") == "reference" and r.get("id") == vid:
            role = r.get("role")
            if role in sites:
                sites[role].setdefault(r["owner"], []).append(r["line"])

    def rows(role):
        return [{"id": owner, "lines": sorted(lines)}
                for owner, lines in sorted(sites[role].items())]

    writers = rows("write")
    return {"writer_count": len(writers), "writers": writers,
            "readers": rows("read")}


def _edge_pairs(model):
    return {(e["from"], e["to"]) for e in model.get("edges", ())}


def _adjacency(model, key, other):
    out = {}
    for e in model.get("edges", ()):
        out.setdefault(e[key], set()).add(e[other])
    return out


def _transitive(adjacency, start):
    """The transitive closure of one node over an adjacency map.

    Derived from `edges` rather than read from the closure records, because
    `transitive_callees` is behind the `closure-sets` axis (SPEC 5.6) and
    `edges` is a master collection present in every model. Reading the axis
    instead would make PSS7005 and PSS8003 answerable only for models that
    happened to ask for it - and worse, the counts alone would report equality
    for two closures of the same size with different members.

    Deriving it is what 11.1 says the sets are: derivable from the master.
    Checked against 365 materialised closure records on the reference target
    before this was relied on, with no disagreement.
    """
    seen, stack = set(), [start]
    while stack:
        current = stack.pop()
        for nxt in adjacency.get(current, ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


def _hash_classification(a, b):
    """SPEC 4.6's four values, read off the hash triple."""
    if a.get("hash_full") == b.get("hash_full"):
        return "identical"
    if a.get("hash_body") == b.get("hash_body"):
        return "comment-or-whitespace-only"
    if a.get("hash_raw") == b.get("hash_raw"):
        return "string-literal-only"
    return "code-changed"


def _parameter_signature(symbol):
    return [(p.get("name"), p.get("type"), p.get("mandatory"), p.get("position"))
            for p in symbol.get("parameters", ())]


class _Delta(object):
    """Accumulates records and the per-code tally together.

    Together rather than separately, because the tally is the per-code half of
    SPEC 4.6 and a tally derived after the fact from the records cannot state
    how many subjects were examined - only how many produced output. Every
    subject that is looked at is counted here at the moment it is looked at.
    """

    def __init__(self):
        self.records = []
        self.tally = dict((code, {"examined": 0, "equal": 0, "emitted": 0})
                          for code in COMPARATOR_CODES)

    def equal(self, code):
        self.tally[code]["examined"] += 1
        self.tally[code]["equal"] += 1

    def emit(self, code, subject, subject_kind, equality=None, detail=None):
        slot = self.tally[code]
        slot["examined"] += 1
        slot["emitted"] += 1
        record = {"code": code, "subject": subject,
                  "subject_kind": subject_kind}
        if equality is not None:
            record["equality"] = equality
        if detail is not None:
            record["detail"] = detail
        self.records.append(record)

    def set_difference(self, code, subject, subject_kind, a_set, b_set):
        """The shape shared by every code that compares two sets."""
        if a_set == b_set:
            self.equal(code)
            return
        self.emit(code, subject, subject_kind, equality="differs",
                  detail={"added": sorted(b_set - a_set),
                          "removed": sorted(a_set - b_set)})


def compare_models(model_a, model_b):
    """The neutral fifteen, all of which this build implements.

    Neutral in wording as well as in scope: model A and model B, `differs`
    rather than `changed`. A code that says "changed" has already assumed the
    relation that `trace` exists to declare (SPEC 4.9).
    """
    delta = _Delta()

    fa, fb = _functions(model_a), _functions(model_b)
    ua, ub = _usage_maps(model_a), _usage_maps(model_b)

    # PSS6001/6002/6003 - presence. Every name in either model is examined, and
    # `examined_subjects` below carries them by identifier so that "examined
    # and equal" is answerable per subject and not only per code (SPEC 6.4).
    examined = []
    for present_a, present_b, kind in ((fa, fb, "function"),
                                       (ua, ub, "script-variable")):
        for sid in sorted(set(present_a) | set(present_b)):
            examined.append(sid)
            in_a, in_b = sid in present_a, sid in present_b
            if in_a and in_b:
                delta.equal("PSS6003")
            elif in_a:
                delta.emit("PSS6001", sid, kind)
            else:
                delta.emit("PSS6002", sid, kind)

    callees_a = _adjacency(model_a, "from", "to")
    callees_b = _adjacency(model_b, "from", "to")
    callers_a = _adjacency(model_a, "to", "from")
    callers_b = _adjacency(model_b, "to", "from")

    for sid in sorted(set(fa) & set(fb)):
        a, b = fa[sid], fb[sid]

        classification = _hash_classification(a, b)
        if classification == "identical":
            delta.equal("PSS7001")
        else:
            delta.emit("PSS7001", sid, "function", equality="differs",
                       detail={"classification": classification})

        sig_a, sig_b = _parameter_signature(a), _parameter_signature(b)
        if sig_a == sig_b:
            delta.equal("PSS7002")
        else:
            names_a = set(p[0] for p in sig_a)
            names_b = set(p[0] for p in sig_b)
            delta.emit("PSS7002", sid, "function", equality="differs",
                       detail={"added": sorted(names_b - names_a),
                               "removed": sorted(names_a - names_b),
                               "signature_a": [list(p) for p in sig_a],
                               "signature_b": [list(p) for p in sig_b]})

        direct_a = callees_a.get(sid, set())
        direct_b = callees_b.get(sid, set())
        delta.set_difference("PSS7003", sid, "function", direct_a, direct_b)
        delta.set_difference("PSS7004", sid, "function",
                             callers_a.get(sid, set()),
                             callers_b.get(sid, set()))

        # PSS7005 (SPEC 11.3): the direct callee set crossed with the
        # transitive closure. `downstream-changed` is the cell that earns the
        # code - a function whose own call list is untouched but whose
        # reachable set moved, which is to say a function affected by a change
        # it does not contain and that no textual diff of it will show.
        closure_a = _transitive(callees_a, sid)
        closure_b = _transitive(callees_b, sid)
        direct_same = direct_a == direct_b
        closure_same = closure_a == closure_b
        dependency = _PSS7005_CELL[(direct_same, closure_same)]
        if dependency == "dependencies-unchanged":
            delta.equal("PSS7005")
        else:
            delta.emit("PSS7005", sid, "function", equality="differs",
                       detail={"classification": dependency})

        # PSS7006 (SPEC 11.4): text crossed with dependency context. The
        # `dependency-only` cell names a function that was not edited and may
        # still behave differently; it appears in no hash and no diff. The
        # value names are neutral by specification - no priority is attached,
        # because priority is a judgement and belongs to the caller (1.2).
        text_same = classification == "identical"
        combined = _PSS7006_CELL[(text_same, direct_same and closure_same)]
        if combined == "unchanged":
            delta.equal("PSS7006")
        else:
            delta.emit("PSS7006", sid, "function", equality="differs",
                       detail={"classification": combined})

        # PSS8003: the closure difference itself, with the members. PSS7005
        # says a closure moved; this says which functions entered or left it.
        delta.set_difference("PSS8003", sid, "function",
                             closure_a, closure_b)

    for vid in sorted(set(ua) & set(ub)):
        a, b = ua[vid], ub[vid]
        wa, wb = set(a.get("writers", ())), set(b.get("writers", ()))
        ra, rb = set(a.get("readers", ())), set(b.get("readers", ()))
        if (wa, ra) == (wb, rb):
            delta.equal("PSS7007")
            continue
        delta.emit("PSS7007", vid, "script-variable", equality="differs",
                   detail={
                       "baseline_state": _usage_state(model_a, vid),
                       "successor_state": _usage_state(model_b, vid),
                       "writers": {"added": sorted(wb - wa),
                                   "removed": sorted(wa - wb),
                                   "count_a": len(wa), "count_b": len(wb)},
                       "readers": {"added": sorted(rb - ra),
                                   "removed": sorted(ra - rb),
                                   "count_a": len(ra), "count_b": len(rb)}})

    # PSS8001/8002 - edges. The subject is the calling side and the callee goes
    # in `detail`: a delta record has one subject (SPEC 6.4), and the edge store
    # is keyed by (from, to) rather than observed as a symbol.
    #
    # D10, A3-2: the record copies the edge's call-site `lines` (SPEC 5.9)
    # from the model that carries the edge - the reviewers' first question
    # about an added or removed edge was "where", and both rebuilt it by
    # joining the raw models. Copied with .get: a pre-5.9 model carries no
    # `lines`, and the delta transcribes what its input holds, never invents.
    ea, eb = _edge_pairs(model_a), _edge_pairs(model_b)
    edge_index_a = {(e["from"], e["to"]): e for e in model_a.get("edges", ())}
    edge_index_b = {(e["from"], e["to"]): e for e in model_b.get("edges", ())}
    for code, pairs, index in (("PSS8001", sorted(eb - ea), edge_index_b),
                               ("PSS8002", sorted(ea - eb), edge_index_a)):
        for caller, callee in pairs:
            detail = {"callee": callee}
            lines = index.get((caller, callee), {}).get("lines")
            if lines is not None:
                detail["lines"] = lines
            delta.emit(code, caller, "function", detail=detail)

    # PSS8004: a soft reference's resolution state differs - most importantly a
    # string literal that matches a declared name in one model and matches none
    # in the other. That is the shape a half-finished rename leaves behind, and
    # it is a fact about the literal surface, which is all the tool observes
    # (SPEC 4.4). The subject is the literal rather than a symbol identifier:
    # in the interesting case there is no symbol on one side to name.
    #
    # Equality is over the RESOLUTION only. The record also carries the first
    # site's owner and line (D10, A3-2: both round-2 reviewers rebuilt the
    # position by joining the raw models); a moved site with an unmoved
    # resolution is not a resolution difference and emits nothing.
    soft_a = _soft_resolution(model_a)
    soft_b = _soft_resolution(model_b)
    for literal in sorted(set(soft_a) | set(soft_b)):
        rec_a, rec_b = soft_a.get(literal), soft_b.get(literal)
        in_a = rec_a["matches"] if rec_a else None
        in_b = rec_b["matches"] if rec_b else None
        if in_a == in_b:
            delta.equal("PSS8004")
            continue
        detail = {}
        if in_a is not None:
            detail["resolves_a"] = in_a
        if in_b is not None:
            detail["resolves_b"] = in_b
        # The site of the record the resolution was read from; model B's
        # where it has one (the state the caller usually holds), else A's.
        site = rec_b if rec_b is not None else rec_a
        if site is not None:
            detail["owner"] = site["owner"]
            detail["line"] = site["line"]
        delta.emit("PSS8004", literal, "literal", equality="differs",
                   detail=detail)

    # PSS8008 - the PSS4003 presence difference. Consumer review named this the
    # most review-worthy fact in the specimen change and found it carried by
    # neither candidate shape (SPEC 3.2): a function had stopped being called,
    # and the caller-set difference alone could not say so, because PSS7004
    # reports which callers moved and not whether any remain.
    #
    # No commit identity travels with it. `pss.py` knows two models and nothing
    # about where they came from (SPEC 2.1); a caller wanting per-commit
    # resolution runs `trace` over adjacent generations, where a sequence of
    # these facts - a loss and a later gain among them - is the correct
    # representation rather than an anomaly.
    uncalled_a = _uncalled(model_a)
    uncalled_b = _uncalled(model_b)
    for sid in sorted(set(fa) | set(fb)):
        in_a, in_b = sid in uncalled_a, sid in uncalled_b
        if in_a == in_b:
            delta.equal("PSS8008")
            continue
        detail = {"direction": "gained" if in_b else "lost"}
        # SPEC 4.7: both models' named_by_literal, where the function is in
        # both. The key is absent rather than false when a model does not
        # carry it, following the model's own omit-rather-than-emit-false
        # convention - so a reader is told what was observed, not what was
        # assumed.
        if sid in fa and sid in fb:
            for label, table in (("named_by_literal_a", uncalled_a),
                                 ("named_by_literal_b", uncalled_b)):
                record = table.get(sid)
                if record is not None and record.get("named_by_literal"):
                    detail[label] = True
        delta.emit("PSS8008", sid, "function", detail=detail)

    return delta, examined


def _soft_resolution(model):
    """Each soft-reference literal: what it resolves to (or None), plus the
    first site's owner and line.

    A literal appearing at several sites resolves the same way at all of them -
    resolution is name matching, not position - so the map is keyed by literal
    and `matches` is read once. `None` means the literal matched no declared
    name in this model, which is the state that matters: a literal that
    resolved in one model and not the other is what a half-finished rename
    leaves behind. The site kept is the FIRST record's (document order);
    further sites are derivable from that model's own soft_references
    (SPEC 6.4: the delta copies, it does not restate collections).
    """
    out = {}
    for record in model.get("soft_references", ()):
        literal = record.get("literal")
        if literal is None or literal in out:
            continue
        out[literal] = {"matches": record.get("matches"),
                        "owner": record.get("owner"),
                        "line": record.get("line")}
    return out


def _uncalled(model):
    """The PSS4003 records, by function identifier.

    PSS4003 says a function has no static caller and no top-level invocation.
    It does not say the function is unreachable, and this comparator does not
    upgrade it: what PSS8008 reports is that the *fact's* presence differs
    between two models, which is a smaller and checkable claim.
    """
    return {c["id"]: c for c in model.get("closures", ())
            if c.get("code") == "PSS4003"}


def trace_models(model_before, model_after):
    """The neutral fifteen plus the three rules of SPEC 12.7.

    A layer, not a second comparator. Everything the neutral codes say holds
    for any two models and is computed once; these three add what only a
    caller's assertion of succession licenses. Each produces a **candidate with
    its evidence** and never a conclusion - the tool cannot tell an omitted
    rename from an ordinary change of value semantics, and saying which is the
    caller's judgement (SPEC 1.2).
    """
    delta, examined = compare_models(model_before, model_after)
    for code in SUCCESSION_CODES:
        delta.tally[code] = {"examined": 0, "equal": 0, "emitted": 0}

    before = _usage_maps(model_before)
    after = _usage_maps(model_after)
    functions_before = _functions(model_before)
    functions_after = _functions(model_after)

    # Which functions changed textually. Rule (a) reads this, and reads it from
    # the same hash triple PSS7001 uses rather than recomputing a notion of
    # "changed" that could disagree with the code the caller already has.
    #
    # The rule is specified over writer and reader *functions*, and `<script>`
    # is not one - it is the top level, has no `PSS7001`, and cannot be
    # classified as changed or unchanged. Treating its absence from the symbol
    # table as "changed" made the rule fire on 106 of 140 variables where the
    # specification measures at most 2 per state pair; the count was the signal
    # that the population was wrong, not the threshold.
    def classified(fid):
        a, b = functions_before.get(fid), functions_after.get(fid)
        if a is None or b is None:
            return None
        return _hash_classification(a, b) == "identical"

    # Rule (a), PSS8006: a writer changed and a reader did not. If the writer
    # renamed the variable and the reader was left behind, the reader still
    # references the old name - but an ordinary change of value semantics looks
    # the same from here, which is why the evidence travels and the verdict
    # does not.
    for vid in sorted(set(before) & set(after)):
        delta.tally["PSS8006"]["examined"] += 1
        writers = sorted(after[vid].get("writers", ()))
        readers = sorted(after[vid].get("readers", ()))
        changed_writers = [w for w in writers if classified(w) is False]
        unchanged_readers = [r for r in readers if classified(r) is True]
        if not (changed_writers and unchanged_readers):
            delta.tally["PSS8006"]["equal"] += 1
            continue
        delta.tally["PSS8006"]["emitted"] += 1
        delta.records.append({
            "code": "PSS8006", "subject": vid,
            "subject_kind": "script-variable",
            "detail": {"changed_writers": changed_writers,
                       "unchanged_readers": unchanged_readers,
                       "baseline_state": _usage_state(model_before, vid),
                       "successor_state": _usage_state(model_after, vid)}})

    # Rule (b), PSS8005: a name appears while an old name persists with reduced
    # usage. A completed rename removes one name and adds one; an incomplete
    # one leaves the old name behind, still read from somewhere.
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    persisting = sorted(set(before) & set(after))

    def usage_counts(record):
        return (len(record.get("writers", ())), len(record.get("readers", ())))

    for new_name in added:
        delta.tally["PSS8005"]["examined"] += 1
        evidence = []
        for old_name in persisting:
            was, now = usage_counts(before[old_name]), usage_counts(after[old_name])
            if now < was:
                evidence.append({
                    "persisting": old_name,
                    "writers_before": was[0], "writers_after": now[0],
                    "readers_before": was[1], "readers_after": now[1]})
        # A removed name whose counts equal the added name's is reported as a
        # correspondence, not as an identification: equal counts are evidence
        # of a pairing and not proof of one (SPEC 12.7 rule (b)).
        new_counts = usage_counts(after[new_name])
        matched = [old for old in removed
                   if usage_counts(before[old]) == new_counts]
        if not evidence and not matched:
            delta.tally["PSS8005"]["equal"] += 1
            continue
        delta.tally["PSS8005"]["emitted"] += 1
        detail = {"added": new_name}
        if evidence:
            detail["persisting_with_reduced_usage"] = evidence
        if matched:
            detail["count_correspondence"] = matched
        delta.records.append({
            "code": "PSS8005", "subject": new_name,
            "subject_kind": "script-variable", "detail": detail})

    # Rule (c), PSS8007: readers and no writers in the after model. Unlike the
    # other two this is decidable within the model - it reports a set that is
    # empty, not a resemblance. It is NOT decidable outside it: the writer set
    # is not a complete account of writing (SPEC 13.2 records four declaration
    # forms this build does not retain), and what an unwritten read does at run
    # time depends on `Set-StrictMode`, which the tool does not observe. So the
    # fact is the empty writer set, and the word "broken" appears nowhere.
    for vid in sorted(after):
        delta.tally["PSS8007"]["examined"] += 1
        record = after[vid]
        readers = sorted(record.get("readers", ()))
        if not readers or record.get("writers"):
            delta.tally["PSS8007"]["equal"] += 1
            continue
        delta.tally["PSS8007"]["emitted"] += 1
        delta.records.append({
            "code": "PSS8007", "subject": vid,
            "subject_kind": "script-variable",
            "detail": {"readers": readers, "writer_count": 0,
                       "baseline_state": (_usage_state(model_before, vid)
                                          if vid in before else None),
                       "successor_state": _usage_state(model_after, vid)}})

    return delta, examined


def _provenance(model_a, model_b, direction):
    """SPEC 6.4: the delta states which two models produced it.

    A delta that cannot name its inputs is not a fact about anything. Both
    reviewers of the pre-implementation specimens raised its absence
    independently (SPEC 3.2).
    """
    return {
        "direction": direction,
        "source_a": {"source": model_a.get("source"),
                     "model_version": model_a.get("model_version"),
                     "pss_version": model_a.get("pss_version")},
        "source_b": {"source": model_b.get("source"),
                     "model_version": model_b.get("model_version"),
                     "pss_version": model_b.get("pss_version")},
    }


def _load_model(path, label):
    if not os.path.isfile(path):
        sys.stderr.write("pss.py: not a readable file: %s\n" % path)
        return None
    with open(path, "r", encoding="utf-8") as fh:
        try:
            return json.load(fh)
        except json.JSONDecodeError as exc:
            sys.stderr.write("pss.py: %s: %s is not valid JSON (%s)\n"
                             % (label, path, exc))
            return None


def _check_preconditions(model_a, model_b, verb):
    """SPEC 5.5 and 5.7. A failure refuses; it does not compare partially.

    Comparing models produced under different contracts is the most direct way
    to manufacture a false delta, so the answer is no answer rather than a
    qualified one.
    """
    va = model_a.get("model_version")
    vb = model_b.get("model_version")
    if va != vb:
        sys.stderr.write(
            "pss.py: %s: PSS9005 - the models carry different model_version "
            "values (%s and %s). A model_version advances whenever the model "
            "emitted for a fixed input can differ (SPEC 5.5), so a delta "
            "across the boundary would report differences the scripts do not "
            "have. No partial comparison is produced.\n" % (verb, va, vb))
        return False

    axes_a = sorted(model_a.get("materialization", {}).get("axes", ()))
    axes_b = sorted(model_b.get("materialization", {}).get("axes", ()))
    if axes_a != axes_b:
        sys.stderr.write(
            "pss.py: %s: PSS9005 - the models materialise different axis sets "
            "(%s and %s). An axis controls how much of a collection is "
            "emitted (SPEC 5.6), so the narrower model would report absences "
            "that are projection and not difference. Use 'slice --axes' to "
            "bring both to one axis set first.\n"
            % (verb, "[%s]" % ", ".join(axes_a) if axes_a else "[]",
               "[%s]" % ", ".join(axes_b) if axes_b else "[]"))
        return False

    scope_a = model_a.get("materialization", {}).get("scope")
    scope_b = model_b.get("materialization", {}).get("scope")
    if scope_a != scope_b:
        sys.stderr.write(
            "pss.py: %s: PSS9005 - the models carry different projection "
            "scopes (%s and %s). A projection selects which records concern "
            "one symbol (SPEC 5.7); comparing across two of them reports the "
            "projection rather than the scripts.\n"
            % (verb, scope_a or "(none)", scope_b or "(none)"))
        return False

    return True


def _delta_document(model_a, model_b, direction, want_all):
    # The verb decides which codes may be said, not how they are computed.
    # `trace` runs the same comparator and adds the rule layer on top, so the
    # succession-only codes cannot leak into `compare` by accident: they are
    # not in the tally `compare` builds at all, and a code absent from the
    # tally reads as "did not run", which is exactly true here (SPEC 4.9, 6.4).
    if direction == "caller-asserted-succession":
        delta, examined = trace_models(model_a, model_b)
    else:
        delta, examined = compare_models(model_a, model_b)

    document = _provenance(model_a, model_b, direction)
    document["delta_records"] = delta.records
    document["surveyed"] = delta.tally

    # SPEC 6.4 (D10, A3-1): the codes this run did NOT evaluate, stated with
    # the reason, keyed by code. Absence from `surveyed` was already the
    # signal; this makes the signal self-describing - both round-2 reviewers
    # proposed it independently. Empty under `trace`, which evaluates all
    # eighteen; `{}` is emitted rather than the key omitted, because an
    # omitted key is the silence SPEC 4.6 forbids.
    catalogue = set(COMPARATOR_CODES) | set(SUCCESSION_CODES)
    not_evaluated = {}
    for code in sorted(catalogue - set(delta.tally)):
        if code in SUCCESSION_CODES:
            not_evaluated[code] = (
                "succession-only: emitted only under trace, which carries "
                "the caller's assertion that model B is a later state of "
                "model A (SPEC 4.9, 12.7)")
        else:  # pragma: no cover - every catalogued code is implemented
            not_evaluated[code] = "not implemented in this build"
    document["not_evaluated"] = not_evaluated

    # SPEC 6.4 (D10, A3-3): the examined population is per-kind counts by
    # default and the full enumeration under --all. Both round-2 reviewers
    # reported never using the enumeration while it dominated the document's
    # bytes; the per-subject question ("was function/X examined?") remains
    # answerable under --all, and the counts cross-check against the
    # presence tally (PSS6001 + PSS6002 + PSS6003 examined = their sum).
    fa, fb = _functions(model_a), _functions(model_b)
    counts = {"function": 0, "script-variable": 0}
    for sid in examined:
        kind = "function" if sid in fa or sid in fb else "script-variable"
        counts[kind] += 1
    document["examined_subjects"] = counts

    # SPEC 5.5: `cost` describes the model, not the script, and two models can
    # be identical in every record and differ only there. Stated in the output
    # rather than applied silently, so the delta is not read as covering
    # everything the models contain.
    document["excluded"] = ["cost"]

    if model_a.get("source", {}).get("path") != \
            model_b.get("source", {}).get("path"):
        document["source_path_differs"] = True

    if want_all:
        document["examined_subjects"] = examined
        document["delta_records"] = _expand_to_all(delta, examined,
                                                   model_a, model_b)
    return document


def _expand_to_all(delta, examined, model_a, model_b):
    """`--all`: state every code for every subject, equality included.

    For a caller that keeps the delta and discards the models, so that the
    record has to stand alone. The default omits equal subjects because the
    intended caller is a language model holding two files (SPEC 2.6) and the
    difference is an order of magnitude - but omitting is a choice about size,
    never about what was measured, which is why `surveyed` is present either
    way.
    """
    emitted = set((r["code"], r["subject"]) for r in delta.records)
    records = list(delta.records)

    fa, fb = _functions(model_a), _functions(model_b)
    ua, ub = _usage_maps(model_a), _usage_maps(model_b)

    for sid in examined:
        if ("PSS6001", sid) in emitted or ("PSS6002", sid) in emitted:
            continue
        kind = "function" if sid in fa or sid in fb else "script-variable"
        records.append({"code": "PSS6003", "subject": sid,
                        "subject_kind": kind})

    for code, population, kind in (
            ("PSS7001", sorted(set(fa) & set(fb)), "function"),
            ("PSS7002", sorted(set(fa) & set(fb)), "function"),
            ("PSS7003", sorted(set(fa) & set(fb)), "function"),
            ("PSS7004", sorted(set(fa) & set(fb)), "function"),
            ("PSS7005", sorted(set(fa) & set(fb)), "function"),
            ("PSS7006", sorted(set(fa) & set(fb)), "function"),
            ("PSS8003", sorted(set(fa) & set(fb)), "function"),
            ("PSS7007", sorted(set(ua) & set(ub)), "script-variable"),
            ("PSS8008", sorted(set(fa) | set(fb)), "function"),
            ("PSS8004", sorted(set(_soft_resolution(model_a))
                               | set(_soft_resolution(model_b))), "literal")):
        for sid in population:
            if (code, sid) in emitted:
                continue
            records.append({"code": code, "subject": sid,
                            "subject_kind": kind, "equality": "equal"})

    records.sort(key=lambda r: (r["code"], r["subject"]))
    return records


def _render_delta_text(document, verb):
    lines = ["==== pss.py %s ====" % verb]
    a = document["source_a"]["source"] or {}
    b = document["source_b"]["source"] or {}
    lines.append("model A    : %s" % a.get("path", "(unknown)"))
    lines.append("model B    : %s" % b.get("path", "(unknown)"))
    lines.append("direction  : %s" % document["direction"])
    lines.append("excluded   : %s" % ", ".join(document["excluded"]))
    if document.get("source_path_differs"):
        lines.append("note       : the two models name different source paths")
    lines.append("")
    lines.append("-- per code (examined / equal / emitted) --")
    for code in sorted(document["surveyed"]):
        t = document["surveyed"][code]
        lines.append("%-8s %6d %8d %9d   %s"
                     % (code, t["examined"], t["equal"], t["emitted"],
                        FACTS.get(code, "")[:44]))
    lines.append("")
    lines.append("-- records --")
    if not document["delta_records"]:
        lines.append("(none: every code above examined its population and "
                     "found it equal)")
    for record in document["delta_records"]:
        detail = record.get("detail")
        lines.append("%-8s %-52s %s"
                     % (record["code"], record["subject"],
                        json.dumps(detail, separators=(',', ':'),
                                   ensure_ascii=False) if detail else
                        record.get("equality", "")))
    lines.append("")
    subjects = document["examined_subjects"]
    # SPEC 6.4: per-kind counts by default, the enumeration under --all. The
    # text channel states the same total either way (SPEC 6.2).
    total = (sum(subjects.values()) if isinstance(subjects, dict)
             else len(subjects))
    lines.append("examined subjects: %d" % total)
    for code, reason in sorted(document.get("not_evaluated", {}).items()):
        lines.append("not evaluated: %s (%s)" % (code, reason))
    return "\n".join(lines) + "\n"


def _run_comparison(args, verb, path_a, path_b, direction):
    model_a = _load_model(path_a, verb)
    if model_a is None:
        return EXIT_ERROR
    model_b = _load_model(path_b, verb)
    if model_b is None:
        return EXIT_ERROR

    if not _check_preconditions(model_a, model_b, verb):
        return EXIT_ERROR

    document = _delta_document(model_a, model_b, direction,
                               getattr(args, "all", False))

    if args.format == "json" or getattr(args, "out", None):
        if getattr(args, "pretty", False):
            text = json.dumps(document, indent=2, ensure_ascii=False)
        else:
            text = json.dumps(document, separators=(',', ':'),
                              ensure_ascii=False)
    else:
        text = _render_delta_text(document, verb)

    out = getattr(args, "out", None)
    payload = text if text.endswith("\n") else text + "\n"
    if out:
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(payload)
    else:
        sys.stdout.write(payload)
    return EXIT_OK


def cmd_compare(args):
    return _run_comparison(args, "compare", args.a, args.b, "unrelated")


def cmd_trace(args):
    return _run_comparison(args, "trace", args.before, args.after,
                           "caller-asserted-succession")


def capabilities_document(parser):
    """Assemble the SPEC 3.1 descriptor from the tool's own declarations.

    Every field here is READ from something the tool already holds - the
    argument parser, FACTS, AXES, MODEL_SCHEMA, IDENTIFIER_FORMS,
    COLLECTION_KEYS, EXIT_CODES, MACHINE_OUTPUTS. Nothing is written out a
    second time. That is the whole design constraint: a descriptor that
    restates a fact becomes a second copy of it, and two copies of one fact
    drift (ADR 0036). It is also why SPEC 13.3 put the schema in the code.

    The subcommand list is taken from the parser rather than from a literal,
    so a subcommand that is added, removed or renamed cannot be missing from
    the descriptor.
    """
    sub = [a for a in parser._subparsers._group_actions
           if isinstance(a, argparse._SubParsersAction)][0]
    subcommands = {}
    for choice in sorted(sub.choices):
        sp = sub.choices[choice]
        opts = sorted(
            o for a in sp._actions for o in a.option_strings
            if o.startswith("--") and o != "--help")
        subcommands[choice] = {
            "summary": next((c.help for c in sub._choices_actions
                             if c.dest == choice), None),
            "options": opts,
        }

    formats = sorted(next(
        (a.choices for a in sub.choices["survey"]._actions
         if a.dest == "format"), ()))

    return {
        "descriptor": "pss-capabilities",
        "spec": "SPEC 3.1",
        "pss_version": __version__,
        "model_version": MODEL_VERSION,
        "subcommands": subcommands,
        "formats": formats,
        "machine_formats": list(MACHINE_FORMATS),
        "exit_codes": dict(EXIT_CODES),
        "axes": dict(AXES),
        "axes_alias": dict(AXES_ALIAS),
        "global_flags": dict(GLOBAL_FLAGS),
        "facts": dict(FACTS),
        "model_schema": dict(MODEL_SCHEMA),
        "nullable_paths": dict(NULLABLE_PATHS),
        "slice_projection": json.loads(json.dumps(SLICE_PROJECTION)),
        "record_variants": json.loads(json.dumps(RECORD_VARIANTS)),
        "record_variant_path_index": record_variant_path_index(),
        "identifier_forms": dict(IDENTIFIER_FORMS),
        "script_owner": SCRIPT_OWNER,
        "collection_keys": {
            c: {f: (list(v[f]) if v[f] else (None if f == "unique" else []))
                for f in COLLECTION_KEY_FIELDS}
            for c, v in COLLECTION_KEYS.items()
        },
        "machine_outputs": {k: dict(v) for k, v in MACHINE_OUTPUTS.items()},
        "ordering": "Collections are emitted in a fixed key order and records "
                    "in a documented sort order; two runs over one input are "
                    "byte-identical (SPEC 5.4). A caller may join or diff two "
                    "models outside the tool on that basis.",
    }


def cmd_capabilities(parser):
    json.dump(capabilities_document(parser), sys.stdout,
              sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    sys.stdout.write("\n")
    return EXIT_OK


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
    if any(t in AXES_ALIAS for t in tokens):
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
    # Constructed from GLOBAL_FLAGS (SPEC 3.1): one declaration, read by
    # the parser here and by the descriptor - the two cannot part.
    for flag, help_text in GLOBAL_FLAGS.items():
        p.add_argument(flag, action="store_true", help=help_text)
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

    cp = sub.add_parser("compare", help="state the differences between two "
                                        "models, claiming no relation between "
                                        "them")
    cp.add_argument("a")
    cp.add_argument("b")
    cp.add_argument("--format", choices=("text", "json"), default="text")
    cp.add_argument("--out", metavar="PATH",
                     help="write the delta document here instead of stdout")
    cp.add_argument("--pretty", action="store_true",
                     help="indent the JSON delta document")
    cp.add_argument("--all", action="store_true",
                     help="state every code for every subject, equality "
                          "included, for a delta that must stand alone "
                          "without the models (SPEC 6.4)")
    cp.set_defaults(func=cmd_compare)

    tp = sub.add_parser("trace", help="state the differences between two models "
                                      "where the caller asserts the second is a "
                                      "later state of the first")
    tp.add_argument("before")
    tp.add_argument("after")
    tp.add_argument("--format", choices=("text", "json"), default="text")
    tp.add_argument("--out", metavar="PATH",
                     help="write the delta document here instead of stdout")
    tp.add_argument("--pretty", action="store_true",
                     help="indent the JSON delta document")
    tp.add_argument("--all", action="store_true",
                     help="state every code for every subject, equality "
                          "included, for a delta that must stand alone "
                          "without the models (SPEC 6.4)")
    tp.set_defaults(func=cmd_trace)

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
    if args.capabilities:
        return cmd_capabilities(parser)
    if args.self_check:
        return self_check()
    if not getattr(args, "command", None):
        parser.print_help()
        return EXIT_ERROR
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
