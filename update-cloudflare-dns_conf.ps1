##### Config

## DNS A record or records to be updated
## Each record is required to have the the following:
##   1. Which IP should be used for the record: internal/external
##      Internal interface will be chosen automaticly as a primary default interface
##   2. Record to update
##   3. The proxied status (Use Cloudflare proxy on dns record true/false)
##   4. cache time (60-7200 in seconds or 1 for Auto)
$dns_records = [ordered]@{
	record1 = @{
		what_ip = "internal";
		record = "ddns.example.com";
		proxied = $false;
		ttl = 1;
	} #record 1 
	record2 = @{
		what_ip = "external";
		record = "ddns2.example.com";
		proxied = $false; 
		ttl = 1;
	} #record 2
}
## Use IPv6
$IPv6 = $false
## if use DoH to query the current IP address
$DNS_over_HTTPS = $false

## Cloudflare's Zone ID - Cloudflare Dashboard -> Websites -> example.com -> Overview -> API Zone ID on right-hand sidebar
$zoneid = "ChangeMe"
## Cloudflare Zone API Token - Instructions: https://github.com/fire1ce/DDNS-Cloudflare-PowerShell/blob/main/README.md#creating-cloudflare-api-token
$cloudflare_zone_api_token = "ChangeMe"

## Comment to put on the updated record
$comment = "Updated with fire1ce's DDNS-Cloudflare-PowerShell script $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"

## Telegram Notifications yes/no (only sent if DNS is updated)
$notify_me_telegram = "no"
## Telegram Chat ID
$telegram_chat_id = "ChangeMe"
## Telegram Bot API Key
$telegram_bot_API_Token = "ChangeMe"

## Discord Server Notifications yes/no (only sent if DNS is updated)
$notify_me_discord = "no"
## Discord Webhook URL (create a webhook on your Discord server via Server Settings > Integrations)
$discord_webhook_URL = "ChangeMe"