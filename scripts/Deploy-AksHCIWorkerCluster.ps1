#Deploy Worker Cluster

#Retreive AksHCI logs for Worker Cluster deployment
New-AksHciCluster -clusterName worker-cls1 -kubernetesVersion v1.18.8 `
    -controlPlaneNodeCount 1 -linuxNodeCount 1 -windowsNodeCount 0 `
    -controlplaneVmSize default -loadBalancerVmSize default -linuxNodeVmSize default