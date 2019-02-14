#!/bin/bash
# Script to list AHV based VM information
# Author: Magnus Andersson, Sr Staff Solution Architect @Nutanix.
# Date: 2019-02-14
#
# Information:
# - You can run the script against either Prism Element (traditional Nutanix Cluster) or both Prism Element and Prism Central.
# - VM Create Date, Self Service Portal and vNUMA information is available only if you include Prism Central.
#
# Version 2.4 - Added VM Categories information and VM UUID. Categories are reported in the format of Name-Value e.g. DMZ-Customer01. Requires Prism Central. Fixed VM Memory reporting which could get corrupted in certain situation.
# Version 2.3 - Script adjusted to display a cleaner output during runtime, correctly manage VM Annotation/descriptions field including comma.
# Version 2.2 - Added VM Description Field and vNUMA information. Adjusted scirpt to recent API changes for disk reporting.
# Version 2.1 - Added VM Create date and changed VG storage allocation to match changes in the API.
# Version 2.0 - To support AOS 5.5 with Self Service Portal moved to Prism Central (PC) the capability to connect to PC for SSP related information has been added
# Version 1.1 - Added information about Volume Groups and Remote Protection Domain Snapshots
# Version 1.0 - Initial Release
#
#---------------------------------------
# Define your variables in this section
#---------------------------------------
#
# !!!! Do not remove the two double quotes around the values !!!!
#
# Specify output file directory - Do not include a slash at the end
directory="/Users/magander/Documents/script/REST"
#
# Specify Nutanix Cluster FQDN, User and Password
clusterfqdn="10.10.100.130"
user="admin"
passwd="secret"
#
# Specify if Nutanix Prism Central s in use. If yes, specify FQDN, User and Password. Prism Central isi required to get Self Service Portal VM Project belonging and SSP VM owner information
#
# Is Prism central in use. Available options are Y and N
pcinuse="y"
pcfqdn="10.10.100.140"
pcuser="admin"
pcpasswd="secret"
#
# Uncomment the below line to enable verbose debuggning mode - you'll see a ton of stuff on the screen.
# set -xv
#
#-------------------------------------------
# Do not edit anything below this line text
#-------------------------------------------
#
# Define Script Global REST API URLs
urlgetcluster="https://"$clusterfqdn":9440/api/nutanix/v2.0/clusters/"
urlgetvms="https://"$clusterfqdn":9440/api/nutanix/v2.0/vms/?include_vm_disk_config=true&include_vm_nic_config=true"
urlgetahvsnaps="https://"$clusterfqdn":9440/api/nutanix/v2.0/snapshots/"
urlgetlocalpdsnaps="https://"$clusterfqdn":9440/api/nutanix/v2.0/protection_domains/dr_snapshots/?full_details=true"
urlgetremotepdsnaps="https://"$clusterfqdn":9440/api/nutanix/v2.0/remote_sites/dr_snapshots/?full_details=true"
urlgetahvhosts="https://"$clusterfqdn":9440/api/nutanix/v2.0/hosts/"
urlgetnetworks="https://"$clusterfqdn":9440/api/nutanix/v2.0/networks/"
urlgetvdisks="https://"$clusterfqdn":9440/api/nutanix/v2.0/virtual_disks/"
urlgetvgs="https://"$clusterfqdn":9440/api/nutanix/v3/volume_groups/list"
#
# Define Script Global REST API Calls
getcluster=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetcluster`
getvms=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetvms`
getahvsnaps=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetahvsnaps`
getpdlocalsnaps=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetlocalpdsnaps`
getpdremotesnaps=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetremotepdsnaps`
gethosts=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetahvhosts`
getnetworks=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetnetworks`
getvdisks=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetvdisks`
getvgs=`curl -s -k -u $user:$passwd -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -d "{
  \"kind\": \"volume_group\"
}" $urlgetvgs`
#
#
# Find cluster name
clustername=`echo $getcluster | python -m json.tool | grep -A 1 multicluster | grep -w name | awk -F "\"" '{print $4}' | awk -F " " '{print $1}'`
#
#
# Get date
d=`date +%F`
#
#
# Script output file
file="$directory/"$d"-Nutanix_Cluster-"$clustername"-VM_Report.csv"
#
# Clean any existing report files with same name as the one being generated
echo > $file
#
if [ $pcinuse == "Y" ] || [ $pcinuse == "y" ]
    then
        echo Both Nutanix Prism Central $pcfqdn and Nutanix Prism Element $clusterfqdn will be used to collect information.
        echo ""
        echo "VM Name,VM Desription,VM Categories,VM Create Date,Total Number of vCPUs,Number of CPUs,Number of Cores per vCPU,Memory GB,vNUMA,Disk Usage GB, Disk Allocated GB,Number of VGs, VG Names,VG Disk Allocated GB,Flash Mode Enabled,AHV Snapshots,Local Protection Domain Snapshots,Remote Protection Domain Snapshots,IP Address/IP Addresses,Network Placement,AHV Host placement,Self Service Portal Project, Self Service Portal VM Owner, VM UUID " > $file
            else
        echo Nutanix Prism Element $clusterfqdn will be used to collect information.
        echo ""
        echo "VM Name,VM Description,Total Number of vCPUs,Number of CPUs,Number of Cores per vCPU,Memory GB,Disk Usage GB, Disk Allocated GB,Number of VGs, VG Names,VG Disk Allocated GB,Flash Mode Enabled,AHV Snapshots,Local Protection Domain Snapshots,Remote Protection Domain Snapshots,IP Address/IP Addresses,Network Placement,AHV Host placement, VM UUID " > $file
fi
#
# Get VM uuids
vmuuids=`echo $getvms | python -m json.tool | grep -w uuid | awk -F":" '{print $2}' | awk -F"\"" '{print $2}'`
#
# Create the report
for i in $vmuuids ;
    do
        # Get VM UUID
        vmid=$i
        #
        # Define VM REST API v2 url
        urlgetvm="https://"$clusterfqdn":9440/PrismGateway/services/rest/v2.0/vms/$i?include_vm_disk_config=true&include_vm_nic_config=true"
        # Get REST v2 VM info
        vminfo=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetvm`
        #
        # Get VM name
        vmname=`echo $vminfo | python -m json.tool |grep -i name | awk -F"\"" '{print $4}'`
        echo "Creating reporting input for VM $vmname now ....."
        vmdesc1=`echo $vminfo | python -m json.tool |grep -i description | awk -F"\"" '{print $4}'`
        vmdesc2=`if [[ $vmdesc1 == *[,]* ]] ; then
              echo $vmdesc1 | awk '{ print "\""$0"\""}'
            else
              echo $vmdesc1
            fi`
        vmdescription=`if [ -z "$vmdesc2" ] ; then
                            echo "No VM Description Information Available"
                            else
                            echo $vmdesc2
                        fi`
        # VM create date and SSP section
        #echo "$vmdescription"
    if [ $pcinuse == "Y" ] || [ $pcinuse == "y" ]
            then
                # Define VM REST API v3 url
                pcvminfourl="https://"$pcfqdn":9440/api/nutanix/v3/vms/$i"
                # Get REST v3 VM info
                pcvminfo=`curl -s -k -u $pcuser:$pcpasswd -X GET --header 'Accept: application/json' $pcvminfourl`
                #Get VM Create Date
                vmcreatedinfo=`echo $pcvminfo | python -m json.tool | grep -i creation_time | awk -F"\"" '{print $4}' | head -c 10`
                vmcreatedate=`if [ -z "$vmcreatedinfo" ] ; then
                            echo "No VM Create Date Information Available"
                            else
                            echo $vmcreatedinfo
                        fi`
                # Get vNUMA Information
                vnuma=`echo $pcvminfo | python -m json.tool | grep -m1 -i num_vnuma_nodes | awk -F":" '{print $2}' | awk -F"\ " '{print $1}'`
                vnumainfo=`if [[ $vnuma == 0 ]]; then
                            echo "vNUMA Not Configured"
                            else
                            echo $vnuma
                            fi`
                # Get Self Service Project Project
                sspprojectinfo=`echo $pcvminfo | python -m json.tool | grep -A 1 -i project | grep -i name | grep -v '@' | awk -F"\"" '{print $4}'`
                sspproject=`if [ -z "$sspprojectinfo" ] ; then
                            echo "Missing Information or VM not in SSP Project"
                            else
                            echo $sspprojectinfo
                        fi`
                # Get Self Service Portal Owner
                sspownerinfo=`echo $pcvminfo | python -m json.tool | grep -A 2 owner_reference | grep -i name | awk -F"\"" '{print $4}' | awk -F"\@" '{print $1}'`
                sspowner=`if [ -z "$sspownerinfo" ] ; then
                        echo "N/A"
                            else
                        echo $sspownerinfo
                    fi`
               # Get VM categories
               category=`echo $pcvminfo | python -m json.tool | sed -n -e '/categories/,/},/ p' | awk -F"categories" '{print $1}' | sed  's/\"/\ /g' | sed  's/\}/\ /g'| sed  's/\,/\ /g' | sed  's/\:/-/g' | sed -e 's/ //g' | sed '/^[[:space:]]*$/d'`
               categories=`if [[ $category == *"creation"* ]]; then
                        echo "N/A"
                      else
                        echo $category
                      fi`
        fi
    # Get VM Power State
        vmpowerstate=`echo $vminfo | python -m json.tool |grep -i power_state | awk -F"\"" '{print $4}'`
        # Get CPU configuration
        num_vcpus=`echo $vminfo | python -m json.tool |grep -i num_vcpus | awk -F" " '{print $2}' | awk -F"," '{print $1}'`
        num_cores_per_vcpu=`echo $vminfo | python -m json.tool | grep -i num_cores_per_vcpu | awk -F" " '{print $2}' | awk -F"," '{print $1}'`
        vCPUs=`echo $(($num_vcpus*$num_cores_per_vcpu))`
        # Get Memory configuration
        memory=`echo $vminfo | python -m json.tool |grep -i memory_mb | awk -F" " '{print $2}' | awk -F"," '{print $1/1024}' | sed  's/\,.*//'`
        # Get IP Information
        ipaddress=`echo $vminfo | python -m json.tool | grep -iw ip_address | awk -F "\"" '{print $4}'`
        ipinfo=`if [ -z "$ipaddress" ] ; then
                    echo "No IP Address Information Available"
                    else
                    echo $ipaddress
                  fi`
        # Get network placement
        network=`echo $vminfo | python -m json.tool | grep -i network_uuid | awk -F "\"" '{print $4}'`
            networkname=`for a in $network ; do
                echo $getnetworks | python -m json.tool | grep -B 1 $a | grep -w name | awk -F "\"" '{print $4}'
                       done`
                # Get AHV based snapshots
        ahvsnaps=`echo $getahvsnaps | python -m json.tool | grep $i | wc -l | awk -F"\ " '{print $1}'`
        # Get Local Protection Domain snapshots
        pdlocalsnaps=`echo $getpdlocalsnaps | python -m json.tool | grep $i | wc -l | awk -F"\ " '{print $1}'`
        # Get Remote Protection Domain snapshots
        pdremotesnaps=`echo $getpdremotesnaps | python -m json.tool | grep $i | wc -l | awk -F"\ " '{print $1}'`
        # Get VM to AHV placement
        ahvhostuuid=`echo $vminfo | python -m json.tool | grep -w host_uuid | awk -F "\"" '{print $4}'`
        urlgetahvhostname="https://"$clusterfqdn":9440/api/nutanix/v2.0/hosts/$ahvhostuuid?projection=BASIC_INFO"
        ahvhostinfo=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetahvhostname`
        #echo "ahvhostinfo" $ahvhostinfo
        urlgetahvhostname="https://"$clusterfqdn":9440/api/nutanix/v2.0/hosts/$ahvhostuuid"
        ahvhostname=`if [ -z "$ahvhostuuid" ]
            then
                echo " "
            else
                echo \$ahvhostinfo  | python -m json.tool | grep -B 6 -w num_cpu_cores | grep -w name | awk -F "\"" '{print $4}'
           fi`
        ahvhostplacement=`if [ "$vmpowerstate" == "off" ] ; then
                   echo "VM Not Powered On"
                else
                    echo $ahvhostname
                fi`
        # Define VM REST API v3 url
        urlgetvmV3="https://"$clusterfqdn":9440/api/nutanix/v3/vms/$i"
        # Get REST v3 VM info
        vminfov3=`curl -s -k -u $user:$passwd -X GET --header 'Accept: application/json' $urlgetvmV3`
         # Get Volume Group Allocaltion information
         vgbaseinfo=`echo $vminfov3 | python -m json.tool | grep -A 2 -i volume_group_reference | grep  -i uuid | awk -F"\"" '{print $4}' | sort | uniq`
        #echo "vgbaseinfo" $vgbaseinfo
        vgbasenames=`if [ -z "$vgbaseinfo" ] ; then
                    echo "N/A"
                     else
                    echo \$getvgs | python -m json.tool | grep -B 7 $i | sort | grep name |  awk -F"\"" '{print $4}' | uniq
                  fi`
        vgbasenumber=`if [ "$vgbasenames"  == "N/A" ] ; then
                    echo "VGs not in use"
                     else
                    echo \$vgbasenames | wc -w | awk -F"\ " '{print $1}'
                  fi`
        vgbaseallocation=`if [ -z "$vgbasenames" ] ; then
                   exit
                        else
                    for c in $vgbasenames ; do
                        echo \$getvgs | python -m json.tool | grep -A 5 -i $c- | grep -i size_mib | uniq | awk -F":" '{print $2}' | awk -F"\ " '{print $1}' | awk '{print $1/1024}'
                        done
                  fi`
        vgstringarray=($vgbaseallocation)
        vgtotalloc=0
                        for i in "${vgstringarray[@]}"; do
                           vgtotalloc=$(echo $vgtotalloc + $i | bc -l)
                        done
        vgtotallocation=`if [ $vgtotalloc == 0 ] ; then
                             echo "N/A"
                                else
                            echo $vgtotalloc
                         fi`
        # Get vDisk allocation in GB
        vdisksallocation=`echo $vminfo | python -m json.tool | grep -A 8 "\"is_cdrom\": false" | grep size | awk -F ":" '{print $2}' | awk '{f1+=$1;f2+=$2} END{print f1/(1024*1024*1024)}'`
        formatvdisksallocation=`echo $vdisksallocation | sed 's/\,/./'`
        # Get vDisk utilization in GB
        vdiskids=`echo $vminfo | python -m json.tool | grep -B 3 "\"is_cdrom\": false" | awk -F "\"" '{print $4}'`
        vdiskutilization=`for b in $vdiskids ; do
                    echo $getvdisks | python -m json.tool | grep -A 100 $b | grep controller_user_bytes | awk -F":" '{print $2}' | awk -F"\"" '{print $2}' | awk '{print $1/1024/1024/1024}'  | awk '{printf("%.2f\n",$1)}'
                    done`
        formatvdiskutilization=`for i in $vdiskutilization ; do
                                    echo $i | sed 's/\,/./'
                                done`
        vdiskstringarray=($formatvdiskutilization)
        vdiskutilizationtotal=0
                     for i in "${vdiskstringarray[@]}"; do
                         vdiskutilizationtotal=$(echo $vdiskutilizationtotal + $i | bc )
                     done
        # Get Flash Mode Configuration
        flashinfo=`echo $vminfo | python -m json.tool | grep -i flash_mode_enabled | awk -F ":" '{print $2}'`
        flashmode=`if [[ $flashinfo == *"true"* ]]; then
                echo "Yes"
                        else
                echo "No"
            fi`
# Put the information into the report
if [ $pcinuse == "Y" ] || [ $pcinuse == "y" ]
    then
        echo $vmname,$vmdescription,$categories,$vmcreatedate,$vCPUs,$num_vcpus,$num_cores_per_vcpu,$memory,$vnumainfo,$vdiskutilizationtotal,$formatvdisksallocation,$vgbasenumber,$vgbasenames,$vgtotallocation,$flashmode,$ahvsnaps,$pdlocalsnaps,$pdremotesnaps,$ipinfo,$networkname,$ahvhostplacement,$sspproject,$sspowner,$vmid >> $file
    else
        echo $vmname,$vmdescription,$vCPUs,$num_vcpus,$num_cores_per_vcpu,$memory,$vdiskutilizationtotal,$formatvdisksallocation,$vgbasenumber,$vgbasenames,$vgtotallocation,$flashmode,$ahvsnaps,$pdlocalsnaps,$pdremotesnaps,$ipinfo,$networkname,$ahvhostplacement,$vmid >> $file
fi
#
# Closing out the entire script
done
