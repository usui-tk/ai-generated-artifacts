# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-parsestring version=0.1.0 hash=ece100d0911bf1bb policy=canonical binding=follow-latest >>>
function _CanonicalJson_ParseString {
    param($State)
    $sb = [System.Text.StringBuilder]::new()
    $State.i++   # consume opening quote
    $s = $State.s
    while ($State.i -lt $State.n) {
        $c = $s[$State.i]; $State.i++
        if ($c -eq '"') { return $sb.ToString() }
        if ($c -eq '\') {
            if ($State.i -ge $State.n) { throw "Unterminated escape." }
            $e = $s[$State.i]; $State.i++
            switch ($e) {
                '"'  { [void]$sb.Append('"') }
                '\'  { [void]$sb.Append('\') }
                '/'  { [void]$sb.Append('/') }
                'b'  { [void]$sb.Append([char]0x08) }
                't'  { [void]$sb.Append([char]0x09) }
                'n'  { [void]$sb.Append([char]0x0A) }
                'f'  { [void]$sb.Append([char]0x0C) }
                'r'  { [void]$sb.Append([char]0x0D) }
                'u'  {
                    if ($State.i + 4 -gt $State.n) { throw "Bad \u escape." }
                    $hex = $s.Substring($State.i, 4); $State.i += 4
                    [void]$sb.Append([char][System.Convert]::ToInt32($hex, 16))
                }
                default { throw "Bad escape '\$e' at position $($State.i)." }
            }
        } else {
            [void]$sb.Append($c)
        }
    }
    throw "Unterminated string."
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-parsestring <<<
