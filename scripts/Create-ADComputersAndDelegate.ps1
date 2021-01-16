#variables
$wac = "wac"
$AzureStackHCIHosts = Get-VM hpv*
$AzureStackHCIClusterName = "hci01"
$servers = $AzureStackHCIHosts.Name + $AzureStackHCIClusterName
$ouName = "Cluster01"

#New organizational Unit for cluster
$dn = New-ADOrganizationalUnit -Name $ouName -PassThru

#Get Wac Computer Object
$wacObject = Get-AdComputer -Identity $wac

#Creates Azure Stack HCI hosts and Cluster CNO
$servers | ForEach-Object {New-ADComputer -Name $_ -Path $dn -PrincipalsAllowedToDelegateToAccount $wacObject -Enabled $false}

#read OU DACL
$acl = Get-Acl -Path "AD:\$dn"

# Set properties to allow Cluster CNO to Full Control on the new OU
$identity = (Get-ADComputer -Identity $AzureStackHCIClusterName)
$principal = New-Object System.Security.Principal.SecurityIdentifier ($identity).SID
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($principal, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, [System.Security.AccessControl.AccessControlType]::Allow, [DirectoryServices.ActiveDirectorySecurityInheritance]::All)

#modify DACL
$acl.AddAccessRule($ace)

#Re-apply the modified DACL to the OU
Set-ACL -ACLObject $acl -Path "AD:\$dn"