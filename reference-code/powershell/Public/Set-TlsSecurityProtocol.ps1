# >>> CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol version=1.0.0 hash=137ffea3b2034e15 policy=canonical binding=follow-latest >>>
function Set-TlsSecurityProtocol {
    # ====================================================================
    # Enable TLS for outbound HTTPS calls with best-effort multi-version
    # fallback. Tls12 is the baseline (required by most modern endpoints
    # including AMD/Microsoft download servers and Speaker Deck CDN).
    # Tls13 is added when the running .NET supports it (Framework 4.8+,
    # PowerShell 7+, WS2022 / WS2025). Tls11 and Tls (1.0) are added as
    # a defensive fallback for very old environments (WS2016 / WS2019
    # with stock .NET); modern hosts will negotiate Tls13/Tls12 and the
    # legacy bits are ignored by the server. Each enum lookup is wrapped
    # in try/catch because older .NET runtimes raise an enum-value error
    # for protocols they don't recognise.
    # ====================================================================
    $protos = [Net.SecurityProtocolType]::Tls12
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls13 } catch { } # psa-disable-line PSA3004 -- Tls13 enum may not exist on older .NET
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls11 } catch { } # psa-disable-line PSA3004 -- defensive legacy fallback for very old environments
    try { $protos = $protos -bor [Net.SecurityProtocolType]::Tls   } catch { } # psa-disable-line PSA3004 -- defensive legacy fallback for very old environments
    [Net.ServicePointManager]::SecurityProtocol = $protos
}
# <<< CANONICAL unit_id=pwsh.helper.set-tlssecurityprotocol <<<
