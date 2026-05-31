# >>> CANONICAL unit_id=pwsh.helper.write-caution version=0.1.0 hash=29f499cc2213fcc6 policy=canonical binding=follow-latest >>>
function Write-Caution  { param($Msg) _LogLine '[!]' $Msg 'Yellow'   }
# <<< CANONICAL unit_id=pwsh.helper.write-caution <<<
