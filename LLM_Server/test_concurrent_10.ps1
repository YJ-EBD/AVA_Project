$ErrorActionPreference = "Stop"

$Uri = "http://127.0.0.1:8088/v1/chat/completions"
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$Jobs = 1..10 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($Index, $Uri)

        $BodyObject = @{
            model = "ava-qwen3.5-27b-q4km"
            messages = @(
                @{
                    role = "system"
                    content = "You are AVA. Reply briefly in Korean."
                },
                @{
                    role = "user"
                    content = "Concurrent test request number $Index. Reply with OK and the request number in Korean."
                }
            )
            temperature = 0.1
            max_tokens = 48
            stream = $false
        }

        try {
            $Body = $BodyObject | ConvertTo-Json -Depth 8 -Compress
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $Response = Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json; charset=utf-8" -Body $Bytes -TimeoutSec 240
            [pscustomobject]@{
                Index = $Index
                Ok = $true
                Text = $Response.choices[0].message.content
            }
        } catch {
            [pscustomobject]@{
                Index = $Index
                Ok = $false
                Text = $_.Exception.Message
            }
        }
    } -ArgumentList $_, $Uri
}

Wait-Job $Jobs | Out-Null
$Stopwatch.Stop()

$Results = Receive-Job $Jobs | Sort-Object Index
Remove-Job $Jobs

$Results | Format-Table -AutoSize
"ELAPSED_SECONDS=$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 2))"

if (($Results | Where-Object { -not $_.Ok }).Count -gt 0) {
    exit 1
}
