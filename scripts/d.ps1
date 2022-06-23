login-azaccoun

$cred = get-credential adm01
$param = @{myIPforRdp = Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip; adminusername = $cred.UserName; InstallAdminCenterOnDC = $true; AdminPassword = $cred.password}
New-AzResourceGroupDeployment -Name ashci -ResourceGroupName sil-we2 -TemplateUri https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/master/linkedtemplates/azuredeploy.json -TemplateParameterObject $param



Get-AzVMExtension -ResourceGroupName sil-we2 -VMName ashci-dc1 | Where-Object ExtensionType -eq DSC | Remove-AzVMExtension -Force -Verbose
New-AzResourceGroupDeployment -Name ashci -ResourceGroupName sil-we2 -TemplateFile c:\temp\azuredeploy.json -TemplateParameterObject $param


