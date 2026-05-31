# >>> CANONICAL unit_id=pwsh.helper.canonicaljson-writestring version=r01 hash=26049b1f66bab97a policy=canonical binding=follow-latest >>>
function _CanonicalJson_WriteString {
    param([string]$S, [System.Text.StringBuilder]$Sb)
    [void]$Sb.Append('"')
    foreach ($ch in $S.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            0x22 { [void]$Sb.Append('\"'); continue }
            0x5C { [void]$Sb.Append('\\'); continue }
            0x08 { [void]$Sb.Append('\b'); continue }
            0x09 { [void]$Sb.Append('\t'); continue }
            0x0A { [void]$Sb.Append('\n'); continue }
            0x0C { [void]$Sb.Append('\f'); continue }
            0x0D { [void]$Sb.Append('\r'); continue }
            default {
                if ($code -lt 0x20) { [void]$Sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$Sb.Append($ch) }
            }
        }
    }
    [void]$Sb.Append('"')
}
# <<< CANONICAL unit_id=pwsh.helper.canonicaljson-writestring <<<
