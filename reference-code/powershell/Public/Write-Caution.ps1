# >>> CANONICAL unit_id=pwsh.helper.write-caution version=r01 hash=29f499cc2213fcc6 policy=canonical binding=follow-latest >>>
function Write-Caution  { param($Msg) _LogLine '[!]' $Msg 'Yellow'   }
# <<< CANONICAL unit_id=pwsh.helper.write-caution <<<
