#variables
$AzureStackHCIHosts = Get-VM hpv*
$AzureStackHCIClusterName = 'Hci01'
$wac = Get-VM wac
$domainName = (Get-ADDomain).DnsRoot
$dhcpScopeString = '192.168.0.0'

#remove Azure Stack HCI hosts
$AzureStackHCIHosts | Stop-VM -TurnOff -Passthru | Remove-VM -Force
Remove-Item -Path $AzureStackHCIHosts.ConfigurationLocation -Recurse -Force

#remove Azure Stack HCI hosts DNS records, DHCP leases and Disable Computer Accounts
$AzureStackHCIHosts.Name | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
$AzureStackHCIHosts.Name | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
$AzureStackHCIHosts.Name | ForEach-Object {Set-ADComputer -Identity $_ -Enabled $false -ErrorAction SilentlyContinue}
Set-ADComputer -Identity $AzureStackHCIClusterName -Enabled $false -ErrorAction SilentlyContinue

#remove Windows Admin Center host
$wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force
Remove-Item -Path $wac.ConfigurationLocation -Recurse -Force

#remove Windows Admin Center host DNS record, DHCP lease
Get-DnsServerResourceRecord -ZoneName $domainName -Name $wac.Name -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force
Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $wac.Name | Remove-DhcpServerv4Lease

#remove Wac DSC Config
Remove-Item -Path "V:\source\Install-WacUsingChoco.ps1" -Force #in case if updated.

Start-DscConfiguration -UseExisting -Wait -Verbose -Force
