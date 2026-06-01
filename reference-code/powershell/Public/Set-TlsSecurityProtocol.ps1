# >>> CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol version=1.0.0 hash=3d18821524b8b723 policy=canonical binding=follow-latest >>>
function Set-TlsSecurityProtocol {
    <#
    .SYNOPSIS
        Enable TLS 1.2 (and weaker fallbacks) for outbound HTTPS calls.
    .DESCRIPTION
        Required on some Windows PowerShell 5.1 hosts where the default
        SecurityProtocol is still Ssl3 + Tls (1.0). The Microsoft Update
        Catalog (catalog.update.microsoft.com), the Windows Update CDN
        (catalog.s.download.windowsupdate.com) that serves wsusscn2.cab,
        and the GitHub release endpoints (api.github.com / github.com)
        used for the 7-Zip fallback all require TLS 1.2+, so the default
        on older hosts results in a handshake failure unless this is
        set. Tls11 and Tls (1.0) are kept in the bitmask as a
        defensive fallback for very old environments; modern hosts
        will negotiate Tls12.
    #>
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    } catch { } # psa-disable-line PSA3004 -- older PS hosts may lack newer enum values; ignore silently
}
# <<< CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol <<<
