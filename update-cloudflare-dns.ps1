[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

### updateDNS.log file of the last run for debug
$File_LOG = "$PSScriptRoot\update-cloudflare-dns.log"
$FileName = "update-cloudflare-dns.log"

if (!(Test-Path $File_LOG)) {
  New-Item -ItemType File -Path $PSScriptRoot -Name ($FileName) | Out-Null
}

Clear-Content $File_LOG
$DATE = Get-Date -UFormat "%Y/%m/%d %H:%M:%S"
Write-Output "==> $DATE" | Tee-Object $File_LOG -Append

### Load config file
Try {
  . $PSScriptRoot\update-cloudflare-dns_conf.ps1 
}
Catch {
  Write-Output "==> Error! Missing update-cloudflare-dns_conf.ps1 or invalid syntax" | Tee-Object $File_LOG -Append
  Exit
}

# Iterate across each of the keys in the hash table
foreach($current_key in $dns_records.Keys){
	
  # Set the variables for the current key
  $a_record = $dns_records[$current_key]
  $what_ip = $a_record['what_ip']
  $dns_record = $a_record['record']
  $proxied = $a_record['proxied']
  $ttl = $a_record['ttl']
  
  Write-Output "Checking $dns_record before processing..." | Tee-Object $File_LOG -Append

  ### Check validity of "what_ip" parameter
  if ( ($what_ip -ne "external") -and ($what_ip -ne "internal")) {
    Write-Output 'Error! Incorrect "what_ip" parameter choose "external" or "internal"' | Tee-Object $File_LOG -Append
    Exit
  }

  ### Check validity of "record" parameter
  if (!([string]$dns_record) -or $null -eq $dns_record) {
    Write-Output 'Error! Need to provide the dns entry to update ' | Tee-Object $File_LOG -Append
    Continue
  }
  
  ### Check validity of "proxied" parameter
  if (!([string]$proxied) -or ($proxied.GetType().Name.Trim() -ne "Boolean")) {
    Write-Output 'Error! Incorrect "proxied" parameter choose "$true" or "$false" ' | Tee-Object $File_LOG -Append
    Exit
  }

  ### Check validity of "ttl" parameter
  if (( $ttl -lt 60 ) -or ($ttl -gt 7200 ) -and ( $ttl -ne 1 )) {
    Write-Output 'Error! ttl out of range (120-7200) or not set to 1' | Tee-Object $File_LOG -Append
    Exit
  }

  Write-Output "Passed checks, processing $dns_record..." | Tee-Object $File_LOG -Append

  ### Variables to hold values from the various if/functions 
  $ip = $null
  $dns_record_ip = $null
  $is_proxied = $null
  
  ### Get External ip from https://checkip.amazonaws.com
  if ($what_ip -eq 'external') {
    $ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
    if (!([bool]$ip)) {
      Write-Output "Error! Can't get external ip from https://checkip.amazonaws.com" | Tee-Object $File_LOG -Append
      Exit
    }
    Write-Output "==> External IP is: $ip" | Tee-Object $File_LOG -Append
  }
  elseif ($what_ip -eq 'internal') {
    $ip = $((Find-NetRoute -RemoteIPAddress 1.1.1.1).IPAddress|out-string).Trim()
    if (!([bool]$ip) -or ($ip -eq "127.0.0.1")) {
      Write-Output "==>Error! Can't get internal ip address" | Tee-Object $File_LOG -Append
      Exit
    }
    Write-Output "==> Internal IP is $ip" | Tee-Object $File_LOG -Append
  }

  ### Get the dns record id and current proxy status from cloudflare's api when proxied is "true"
  if ($proxied -eq $true) {
    $dns_record_info = @{
      Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record"
      Headers = @{
        "Authorization" = "Bearer $cloudflare_zone_api_token";
        "Content-Type" = "application/json" 
      }
    }

    $response = Invoke-RestMethod @dns_record_info
    if ($response.success -ne "True") {
      Write-Output "Error! Can't get dns record info from cloudflare's api" | Tee-Object $File_LOG -Append
    }
    $is_proxied = $response.result.proxied
    $dns_record_ip = $response.result.content.Trim()
  }
  elseif ($proxied -eq $false) {
      $dns_record_ip = (Resolve-DnsName -Name $dns_record -Server 1.1.1.1 -Type A | Select-Object -First 1).IPAddress.Trim()
    if (![bool]$dns_record_ip) {
      Write-Output "Error! Can't resolve the ${dns_record} via 1.1.1.1 DNS server" | Tee-Object $File_LOG -Append
      Exit
    }
    $is_proxied = $proxied
  }

  ### Check if ip or proxy have changed
  if (($dns_record_ip -eq $ip) -and ($is_proxied -eq $proxied)) {
    Write-Output "==> DNS record IP of $dns_record is $dns_record_ip, no changes needed. Exiting..." | Tee-Object $File_LOG -Append
    Continue
  }

  Write-Output "==> DNS record of $dns_record is: $dns_record_ip. Trying to update..." | Tee-Object $File_LOG -Append

  ### Get the dns record information from cloudflare's api
  $cloudflare_record_info = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }

  $cloudflare_record_info_resposne = Invoke-RestMethod @cloudflare_record_info
  if ($cloudflare_record_info_resposne.success -ne "True") {
    Write-Output "Error! Can't get $dns_record record inforamiton from cloudflare API" | Tee-Object $File_LOG -Append
    Continue
  }

  ### Get the dns record id from response
  $dns_record_id = $cloudflare_record_info_resposne.result.id.Trim()

  ### Push new dns record information to cloudflare's api
  $update_dns_record = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id"
    Method  = 'PUT'
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
    Body    = @{
      "type"    = "A"
      "name"    = $dns_record
      "content" = $ip
      "ttl"     = $ttl
      "proxied" = $proxied
    } | ConvertTo-Json
  }

  $update_dns_record_response = Invoke-RestMethod @update_dns_record
  if ($update_dns_record_response.success -ne "True") {
    Write-Output "Error! Update Failed" | Tee-Object $File_LOG -Append
    Continue
  }

  Write-Output "==> Success!" | Tee-Object $File_LOG -Append
  Write-Output "==> $dns_record DNS Record Updated To: $ip, ttl: $ttl, proxied: $proxied" | Tee-Object $File_LOG -Append


  if ($notify_me_telegram -eq "no" -And $notify_me_discord -eq "no")   {
    Continue
  }

  if ($notify_me_telegram -eq "yes") {
    $telegram_notification = @{
      Uri    = "https://api.telegram.org/bot$telegram_bot_API_Token/sendMessage?chat_id=$telegram_chat_id&text=$dns_record DNS Record Updated To: $ip"
      Method = 'GET'
    }
    $telegram_notification_response = Invoke-RestMethod @telegram_notification
    if ($telegram_notification_response.ok -ne "True") {
      Write-Output "Error! Telegram notification failed" | Tee-Object $File_LOG -Append
      Continue
    }
  }

  if ($notify_me_discord -eq "yes") {
    $discord_message = "$dns_record DNS Record Updated To: $ip (was $dns_record_ip)"
    $discord_payload = [PSCustomObject]@{content = $discord_message} | ConvertTo-Json
    $discord_notification = @{
      Uri    = $discord_webhook_URL
      Method = 'POST'
      Body = $discord_payload
      Headers = @{ "Content-Type" = "application/json" }
    }
    try {
      Invoke-RestMethod @discord_notification
    } catch {
      Write-Host "==> Discord notification request failed. Here are the details for the exception:" | Tee-Object $File_LOG -Append
      Write-Host "==> Request StatusCode:" $_.Exception.Response.StatusCode.value__  | Tee-Object $File_LOG -Append
      Write-Host "==> Request StatusDescription:" $_.Exception.Response.StatusDescription | Tee-Object $File_LOG -Append
    }
    Continue
  }
}