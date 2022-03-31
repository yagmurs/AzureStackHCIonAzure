$CLUSTER_NAME="w-1"
$TENANT_ID="0447fa3f-36f0-4826-8a07-6dd19191ace3"
$SERVER_APP_ID=$(az ad app create --display-name "${CLUSTER_NAME}Server" --identifier-uris "api://${TENANT_ID}/ClientAnyUniqueSuffix" --query appId -o tsv)
$SERVER_APP_ID

az ad app update --id "${SERVER_APP_ID}" --set groupMembershipClaims=All

az ad sp create --id "${SERVER_APP_ID}"
$SERVER_APP_SECRET=$(az ad sp credential reset --name "${SERVER_APP_ID}" --credential-description "ArcSecret" --query password -o tsv)

az ad app permission add --id "${SERVER_APP_ID}" --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
az ad app permission grant --id "${SERVER_APP_ID}" --api 00000003-0000-0000-c000-000000000000

$CLIENT_APP_ID=$(az ad app create --display-name "${CLUSTER_NAME}Client" --native-app --reply-urls "api://${TENANT_ID}/ServerAnyUniqueSuffix" --query appId -o tsv)
$CLIENT_APP_ID

az ad sp create --id "${CLIENT_APP_ID}"

az ad app show --id "${SERVER_APP_ID}" --query "oauth2Permissions[0].id" -o tsv

az ad app permission add --id "${CLIENT_APP_ID}" --api "${SERVER_APP_ID}" --api-permissions a4fbac6e-aa3d-4cbd-85cd-59bb26e0a90e=Scope
az ad app permission grant --id "${CLIENT_APP_ID}" --api "${SERVER_APP_ID}"

$ROLE_ID=$(az role definition create --role-definition ./accessCheck.json --query id -o tsv)

az role assignment create --role "${ROLE_ID}" --assignee "${SERVER_APP_ID}" --scope /subscriptions/4df06176-1e12-4112-b568-0fe6d209bbe2

az config set extension.use_dynamic_install=yes_without_prompt

az connectedk8s enable-features -n w-1 -g sil-we1 --features azure-rbac --app-id "${SERVER_APP_ID}" --app-secret "${SERVER_APP_SECRET}"

$authnBase64 = kubectl get secret azure-arc-guard-manifests -n kube-system -o=jsonpath='{.data.guard-authn-webhook\.yaml}'
$authzBase64 = kubectl get secret azure-arc-guard-manifests -n kube-system -o=jsonpath='{.data.guard-authz-webhook\.yaml}'

[Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($authnBase64)) | out-file -FilePath guard-authn-webhook.yaml -Encoding utf8

[Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($authzBase64)) | out-file -FilePath guard-authz-webhook.yaml -Encoding utf8

scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey .\guard-authn-webhook.yaml clouduser@192.168.1.1:/home/clouduser
scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey .\guard-authz-webhook.yaml clouduser@192.168.1.1:/home/clouduser

scp.exe -i (Get-AksHciConfig).moc.sshPrivateKey clouduser@192.168.1.1

kubectl get secret azure-arc-guard-manifests -n kube-system -o yaml | Out-File -FilePath azure-arc-guard-manifests.yaml -Encoding utf8
kubectl apply -f .\azure-arc-guard-manifests.yaml

$env:kubeconfig= (Get-AksHciConfig).kva.kubeconfig

kubectl get kcp w-1-control-plane


kubectl config set-credentials pamirerdem_microsoft.com#EXT#@ygmrs.onmicrosoft.com `
--auth-provider=azure `
--auth-provider-arg=environment=AzurePublicCloud `
--auth-provider-arg=client-id=$CLIENT_APP_ID `
--auth-provider-arg=tenant-id=$TENANT_ID `
--auth-provider-arg=apiserver-id=$SERVER_APP_ID