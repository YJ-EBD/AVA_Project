$ErrorActionPreference = "Stop"

$Uri = "http://127.0.0.1:8088/v1/chat/completions"
$Body = @'
{
  "model": "ava-qwen3.5-27b-q4km",
  "messages": [
    {
      "role": "system",
      "content": "You are AVA, a Korean enterprise messenger AI assistant. Answer concisely in Korean."
    },
    {
      "role": "user",
      "content": "Reply in Korean. Briefly confirm that the AVA enterprise messenger AI assistant local LLM server is working normally."
    }
  ],
  "temperature": 0.2,
  "max_tokens": 128,
  "stream": false
}
'@

$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
$Response = Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json; charset=utf-8" -Body $Bytes -TimeoutSec 180
$Response.choices[0].message.content
