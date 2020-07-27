#!/bin/bash
echo -e ".  . .  .  . .  .  . .  .  . .  .  . .  .  . .  
   .       .    .  .       .   .   .       .     .
     .  .    ;8:8SSS: . .  ;8;8%SS.  .  .    .    
 .       . tt S%88888:%% %; S;8@888:%t   .     .  
   .  .   .%@88888888@88 %@888888888@8     .  .  .
  .    .   %@88888888888:S@88S88888888:  .   .    
    .    . %XS888888X888.S@S88X8888888.    .    . 
  .   . :;:%@888t %.S%%t:%@8@@SS %8XSt;:.     .   
    .:8 8;88@X@;.;.t8X8X%@XtX;.:;%8@8;:8.8;.     .
  .  8;S8%8@@X88:::X..8 888X88%.t;S 8%XX8@8@8 .   
    .@@@XX8888888t;8@XXX888888 :t8%88%S888888:  . 
  . .888X%8X88%8@;;8XSS.888888; %X8%8%XS8@88t     
     8@88@8888S%@..t8X8Xt888X8X t88XtS.888Stt. .  
  .    S@t8t8%t@%@X%X8%%@:88@8%@@SX8%88S8@.  .    
           ttX S88888Xtt S.S.;8@888Xtt.  ..   .   
  .  .  .  %@X88%@888888.%X8@8S888888@ . ...    . 
   .       %@888X@8888X8:SX@88888888@8.   . . .   
      .  . %XS8888888888:S@S88t8888888.    .      
 . .   .   ;S8%@SXX%;8S. tt8888@88 8X.  .    .  . 
    .    .   t;888t;..    ;t88888X::     .  .     
  .   .    . :::..     .  ...::;.     .       .   
    .   .     .   .  .   . .    . .  .   . .   .  
"


echo "================================================================="

echo "Welcome to the installation script of Full AKS..."
echo "Type your resource group Name:"
read resourceGroupName
echo "What is your deployment name?"
read deploymentName
echo "Which Azure DC you want to deploy your workloads?"
read location
echo "Would you like to deploy an AKS cluster with Windows Containers capability? : (Y/N)"
read templatepath
if [[ $(echo $templatepath | grep -io y) == 'y' ]];then
echo "Proceeding with windows..."
templatepath=wintemplate.json
elif [[ $(echo $templatepath | grep -io n) == 'n' ]];then
echo "Proceeding with linux..."
templatepath=template.json
else
echo "you chose an invalid answer ... quiting the script."
exit 0;
fi
echo "what is your Vnet address prefix for the whole deployment? i.e 10.0.0.0/16"
read VnetAddressPrefix
echo "what is your AKS Subnet prefix? i.e 10.0.1.0/24"
read aksSubnet
echo "what is your app gateway Subnet prefix? i.e 10.0.2.0/24"
read appGWSubnet
echo "what is the internal IP you want to assign to the app Gateway?"
read appgatewayprivIP
echo "How many AKS worker nodes do you need to provision?"
read workercount
az aks get-versions --location $location --output table
echo "What is the k8s version you want to deploy? i.e 1.16.10"
read k8sversion
echo "What is the AKS service CIDR? i.e 10.0.3.0/24"
read aksservicecidr
echo "What is the AKS DNS IP? i.e 10.0.3.10"
read aksdnsIP
echo "Do you want to add Azure Firewall to the deployment? :(Y/N) "
read answer
if [[ $(echo $answer | grep -io y) == 'y' ]];then
echo "What is your firewall name?"
read FW_NAME
echo "what is your AZ Firewall Subnet prefix? i.e 10.0.4.0/24"
read AzFirewallSubnet
elif [[ $(echo $answer | grep -io n) == 'n' ]];then
echo "Proceeding without firewall..."
else
echo "you chose an invalid answer ... quiting the script."
fi

out=$(uname -a)
if [[ $(echo $out | grep -io azure) == 'azure' ]];then

echo "no need to install jq, this is Azure cloud shell"
elif [[ $(echo $out | grep -io linux) == 'Linux' ]];then

apt-get install jq -y
else

brew install jq
fi

az ad sp create-for-rbac --skip-assignment -o json > auth.json
sleep 90
appId=$(jq -r ".appId" auth.json)
password=$(jq -r ".password" auth.json)
objectId=$(az ad sp show --id $appId --query "objectId" -o tsv)


cat <<EOF > parameters.json
{
  "aksServicePrincipalAppId": { "value": "$appId" },
  "aksServicePrincipalClientSecret": { "value": "$password" },
  "aksServicePrincipalObjectId": { "value": "$objectId" },
  "virtualNetworkAddressPrefix": { "value": "$VnetAddressPrefix" },
  "aksSubnetAddressPrefix": { "value": "$aksSubnet" },
  "applicationGatewaySubnetAddressPrefix": { "value": "$appGWSubnet" },
  "aksAgentCount": { "value": $workercount },
  "kubernetesVersion": { "value": "$k8sversion" },
  "aksServiceCIDR": { "value": "$aksservicecidr" },
  "aksDnsServiceIP": { "value": "$aksdnsIP" },
  "aksEnableRBAC": { "value": true }
}
EOF

# create a resource group
az group create -n $resourceGroupName -l $location

# modify the template as needed
az deployment group create \
        -g $resourceGroupName \
        -n $deploymentName \
        --template-file $templatepath \
        --parameters parameters.json
# use the deployment-outputs.json created after deployment to get the cluster name and resource group name
az deployment group show -g $resourceGroupName -n $deploymentName --query "properties.outputs" -o json > deployment-outputs.json

aksClusterName=$(jq -r ".aksClusterName.value" deployment-outputs.json)
resourceGroupName=$(jq -r ".resourceGroupName.value" deployment-outputs.json)
QUERYRESULT=$(az aks list --query "[?name=='$aksClusterName'].{rg:resourceGroup, id:id, loc:location, vnet:agentPoolProfiles[].vnetSubnetId, ver:kubernetesVersion, svpid: servicePrincipalProfile.clientId}" -o json)
KUBE_VNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/virtualNetworks/).*?(?=/)')
KUBE_AGENT_SUBNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/subnets/).*?(?=")')

az network vnet subnet create -g $resourceGroupName --vnet-name $KUBE_VNET_NAME --name AzureFirewallSubnet --address-prefix $AzFirewallSubnet

az aks get-credentials --resource-group $resourceGroupName --name $aksClusterName

kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.5.5/deploy/infra/deployment-rbac.yaml
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

applicationGatewayName=$(jq -r ".applicationGatewayName.value" deployment-outputs.json)
resourceGroupName=$(jq -r ".resourceGroupName.value" deployment-outputs.json)
subscriptionId=$(jq -r ".subscriptionId.value" deployment-outputs.json)
identityClientId=$(jq -r ".identityClientId.value" deployment-outputs.json)
identityResourceId=$(jq -r ".identityResourceId.value" deployment-outputs.json)

wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-config.yaml
sleep 50

sed -i "s|<subscriptionId>|${subscriptionId}|g" helm-config.yaml
sed -i "s|<resourceGroupName>|${resourceGroupName}|g" helm-config.yaml
sed -i "s|<applicationGatewayName>|${applicationGatewayName}|g" helm-config.yaml
sed -i "s|<identityResourceId>|${identityResourceId}|g" helm-config.yaml
sed -i "s|<identityClientId>|${identityClientId}|g" helm-config.yaml
sed -i "s|enabled: false|enabled: true|g" helm-config.yaml
sed -i "s|usePrivateIP: false|usePrivateIP: true|g" helm-config.yaml

helm install ingress-azure \
  -f helm-config.yaml \
  application-gateway-kubernetes-ingress/ingress-azure \
    --set nodeSelector."beta\.kubernetes\.io/os"=linux \
    --version 1.2.0-rc3

QUERYRESULT=$(az aks list --query "[?name=='$aksClusterName'].{rg:resourceGroup, id:id, loc:location, vnet:agentPoolProfiles[].vnetSubnetId, ver:kubernetesVersion, svpid: servicePrincipalProfile.clientId}" -o json)
KUBE_VNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/virtualNetworks/).*?(?=/)')
KUBE_FW_SUBNET_NAME='AzureFirewallSubnet' # this you cannot change
KUBE_AGENT_SUBNET_NAME=$(echo $QUERYRESULT | jq '.[0] .vnet[0]' | grep -oP '(?<=/subnets/).*?(?=")')
#create app gateway Internal Frontend IP
az network application-gateway frontend-ip create --gateway-name $applicationGatewayName --name InternalFrontendIp --private-ip-address $appgatewayprivIP --resource-group $resourceGroupName --subnet 'appgwsubnet' --vnet-name $KUBE_VNET_NAME

if [[ $(echo $answer | grep -io y) == 'y' ]];then
if [[ $(echo $templatepath | grep -io win) == 'win' ]];then

kubectl apply -f aspnetappwin.yaml
else
kubectl apply -f aspnetapp.yaml
fi

az extension add --name azure-firewall

KUBE_AGENT_SUBNET_ID=$(echo $QUERYRESULT | jq '.[0] .vnet[0]')

FW_ROUTE_NAME="${FW_NAME}_fw_r"
FW_ROUTE_TABLE_NAME="${FW_NAME}_fw_rt"
FW_PIP="${FW_NAME}_pip"

HCP_IP=$(kubectl get endpoints -o=jsonpath='{.items[?(@.metadata.name == "kubernetes")].subsets[].addresses[].ip}')

az network firewall create \
    --name $FW_NAME \
    --resource-group $resourceGroupName
az network public-ip create \
    --name $FW_PIP \
    --resource-group $resourceGroupName \
    --allocation-method static \
    --sku standard
az network firewall ip-config create \
    --firewall-name $FW_NAME \
    --name FW-config \
    --public-ip-address $FW_PIP \
    --resource-group $resourceGroupName \
    --vnet-name $KUBE_VNET_NAME
az network firewall update \
    --name $FW_NAME \
    --resource-group $resourceGroupName
az network public-ip show \
    --name $FW_PIP \
    --resource-group $resourceGroupName
FW_PRIVATE_IP="$(az network firewall ip-config list -g $resourceGroupName -f $FW_NAME --query "[?name=='FW-config'].privateIpAddress" --output tsv)"

az network route-table create -g $resourceGroupName --name $FW_ROUTE_TABLE_NAME
az network vnet subnet update --resource-group $resourceGroupName --route-table $FW_ROUTE_TABLE_NAME --vnet-name $KUBE_VNET_NAME --name $KUBE_AGENT_SUBNET_NAME
az network route-table route create --resource-group $resourceGroupName --name $FW_ROUTE_NAME --route-table-name $FW_ROUTE_TABLE_NAME --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FW_PRIVATE_IP --subscription $subscriptionId

FW_PUBLIC_IP=$(az network public-ip show -g $resourceGroupName -n $FW_PIP --query ipAddress)
cleanedIP=${FW_PUBLIC_IP:1:13}
az network firewall network-rule create --firewall-name $FW_NAME --collection-name "aksnetwork" --destination-addresses "$HCP_IP"  --destination-ports 443 9000 --name "allow network" --protocols "TCP" --resource-group $resourceGroupName --source-addresses "*" --action "Allow" --description "aks network rule" --priority 100
az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "aksbasics" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $resourceGroupName --action "Allow" --target-fqdns "*.azmk8s.io" "aksrepos.azurecr.io" "*.blob.core.windows.net" "mcr.microsoft.com" "*.cdn.mscr.io" "management.azure.com" "login.microsoftonline.com" "api.snapcraft.io" "*auth.docker.io" "*cloudflare.docker.io" "*cloudflare.docker.com" "*registry-1.docker.io" --priority 100
az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "akstools" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $resourceGroupName --action "Allow" --target-fqdns "download.opensuse.org" "packages.microsoft.com" "dc.services.visualstudio.com" "*.opinsights.azure.com" "*.monitoring.azure.com" "gov-prod-policy-data.trafficmanager.net" "apt.dockerproject.org" "nvidia.github.io" --priority 101
az network firewall application-rule create  --firewall-name $FW_NAME --collection-name "osupdates" --name "allow network" --protocols http=80 https=443 --source-addresses "*" --resource-group $resourceGroupName --action "Allow" --target-fqdns "download.opensuse.org" "*.ubuntu.com" "packages.microsoft.com" "snapcraft.io" "api.snapcraft.io"  --priority 102

#Getting the ingress public IP of the Ingress of the aspnetapp (will replace this later on with the Internal IP as you should expose the service throught the cluster Internal IP not a load Balancer)
SERVICE_IP=$(kubectl get ingress aspnetapp --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
az network firewall nat-rule create  --firewall-name $FW_NAME --collection-name "inboundlbrules" --name "allow inbound load balancers" --protocols "TCP" --source-addresses "*" --resource-group $resourceGroupName --action "Dnat" --source-addresses "*"  --destination-addresses $cleanedIP --destination-ports 80 --translated-address $SERVICE_IP --translated-port "80"  --priority 101
   
   echo "Your deployment is finished successfully..."
else
if [[ $(echo $templatepath | grep -io win) == 'win' ]];then
sed -i "s|use-private-ip: "true"|use-private-ip: "false"|g" aspnetappwin.yaml
kubectl apply -f aspnetappwin.yaml
else
sed -i "s|use-private-ip: "true"|use-private-ip: "false"|g" aspnetapp.yaml
kubectl apply -f aspnetapp.yaml
fi


   echo "Your deployment is finished successfully..."
fi
