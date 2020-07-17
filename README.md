# AKS Utilities

This project is dedicated to making everyone's life easier when it comes to provisioning Microsoft Azure Kubernetes Service and its related components like Ingress controllers, firewalls, etc...

<b>InstallAKS.sh</b> file is currently deploying AKS with App Gateway v2.0,Azure Firewall and a sample app - all that you have to do is answer couple of questions and the bash script will take care of the rest.

You can choose to deploy windows nodes as well for your windows container workloads.

Feel free to contribute and add more files/functionality to this.

<b>How to Install</b>

git clone https://github.com/kmoussa/AKS.git

cd AKS

chmod +x installAKS.sh 

./installAKS.sh 
