#!/bin/bash
# Name of script: ucd_api_deployment.sh
# Author: Sarath Ullattil
# Date of creation: August, 2020
# Details: This shell is used to integrate uDeploy with Bamboo using Bamboo Script task
#--------------------------------------------------------------------------------------------------------------------------------------------------------------
#Configuration details for UCD API Deployment
app_name=<application_name>
env=<application_environment>
app=<UDeploy_application_name>
component=<UDeploy_component_name>
app_process=<UDeploy_application_process_name>

# Variable from Bamboo build rsult with namespace ucdapi
version=${bamboo.ucdapi.Version}

#Variable from Bamboo deployment configuration
apiuser=${bamboo.ucdapi.user}
apipw=${bamboo.ucdapi.password}

#Initialize status check variables
deploy_status=TRIGGER
deploy_result=PENDING
status_chk_ctr=0


alert_email()
{
echo "Deployment of $app_name version $version failed in $env environment. Please check the logs and take necessary action." >> ALERTEmail.txt
echo -e "\n" >> ALERTEmail.txt
echo "This is an automated notification. Please contact devopssupport@mail.com for any questions." >> ALERTEmail.txt
cat ALERTEmail.txt | mailx -s "ALERT: Deployment Failure Notification || $app_name || $env" -r "DevOps <DO-NOT-REPLY@mail.com>" devopssupport@mail.com
}

success_email()
{
echo "Deployment of $app_name version $version completed successfully in $env environment." >> SuccessEmail.txt
echo -e "\n" >> SuccessEmail.txt
echo "This is an automated notification. Please contact devopssupport@mail.com for any questions." >> SuccessEmail.txt
cat SuccessEmail.txt | mailx -s "Deployment Notification || $app_name || $env" -r "DevOps <DO-NOT-REPLY@mail.com>" dl-stakeholders@mail.com
}

#-----------------------------------------------Start of application deployment process-------------------------------------------------------------------

#import configuration files
echo "Importing the configuration files from local directory"
cp /apps/devops/*.json $working_dir

#update the config files with current values
echo "Update configuration files with required values"
sed -i 's/deploy_component/'"$component"'/g' versionImport.json
sed -i 's/deploy_version/'"$version"'/g' versionImport.json

sed -i 's/deploy_app/'"$app"'/g' applicationDeploy.json
sed -i 's/deploy_process/'"$app_process"'/g' applicationDeploy.json
sed -i 's/deploy_env/'"$env"'/g' applicationDeploy.json
sed -i 's/deploy_component/'"$component"'/g' applicationDeploy.json
sed -i 's/deploy_version/'"$version"'/g' applicationDeploy.json

sed -i 's/deploy_app/'"$app"'/g' serverRestart.json
sed -i 's/deploy_env/'"$env"'/g' serverRestart.json
sed -i 's/restart_process/'"$jvm_process"'/g' serverRestart.json

#import version in udeploy
echo "Trigger version import job in uDeploy"
curl -k -u $apiuser:$apipw https://udeploy.domain.com/cli/component/integrate -X PUT -d @versionImport.json > import_output.txt
import_check=`(cat import_output.txt) | wc -c`
if [ "$import_check" -gt 0 ]
then
echo "Verion import result is - "$(cat import_output.txt)
#Trigger alert mail for DevOps team
alert_email
exit 1
fi

#wait for version import
echo "Wait for version import to complete"
sleep 300

#deploy the version and store the id
echo "Trigger application deployment job in uDeploy"
curl -k -u $apiuser:$apipw https://udeploy.domain.com/cli/applicationProcessRequest/request -X PUT -d @applicationDeploy.json > deploy_output.txt
sleep 10
deploy_check=`echo $(cat deploy_output.txt) | cut -d'"' -f 2`

if [ "$deploy_check" = requestId ] 
then
reqid=`echo $(cat deploy_output.txt) | cut -d'"' -f 4`
else 
echo "Deploy result is - "$(cat deploy_output.txt)
#Trigger alert mail for DevOps team
alert_email
exit 1
fi

#check for deployment status and wait for completion
status_chk_fail_msg="No application process request with id $reqid"
echo "Check for deployment status"
until [ "$deploy_status" = CLOSED ]
do
echo "Deployment task is in-progress. Current status is $deploy_status"
echo "Status check counter is $status_chk_ctr"
if [ "$status_chk_ctr" -gt 30 ]
then
echo "Deployment task is running for more than 15 mins. Please verify the status manually. Fail and exit the job"
#Trigger alert mail for DevOps team
alert_email
exit 1
fi
curl -k -u $apiuser:$apipw https://udeploy.domain.com/cli/applicationProcessRequest/requestStatus?request=$reqid > status_output.txt
status_check=`echo $(cat status_output.txt)`
if [ "$status_chk_fail_msg" = "$status_check" ]
then
echo "Deployment status check result is - "$status_check
#Trigger alert mail for DevOps team
alert_email
exit 1
fi
deploy_status=`echo $(cat status_output.txt) | cut -d'"' -f 4`
deploy_result=`echo $(cat status_output.txt) | cut -d'"' -f 8`
sleep 30
status_chk_ctr=`expr $status_chk_ctr + 1`
done
echo "Deployment task completed. Current status is $deploy_status"

#verify the deployment result
echo "Validate the result of deployment task"
if [ "$deploy_result" = SUCCEEDED ]
then
echo "Deployment of $app for version $version is successful"
else
echo "Deployment of $app for version $version failed. Exit the job"
#Trigger alert mail for DevOps team
alert_email
exit 1
fi

#trigger email for successful deployment
echo "Trigger email for sucessful deployment"
success_email

#exit the job
echo "End of script: ucd_api_deployment.sh"
exit 0