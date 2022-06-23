$cred = get-credential adm01
$param = @{myIPforRdp = Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip; adminusername = $cred.UserName; InstallAdminCenterOnDC = $true; AdminPassword = $cred.password}
New-AzResourceGroupDeployment -Name ashci -ResourceGroupName sil-we2 -TemplateUri https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/master/linkedtemplates/azuredeploy.json -TemplateParameterObject $param
