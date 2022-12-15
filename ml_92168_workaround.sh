#!/bin/bash
### please change the values for next 2 lines
ESurl=https://localhost:9200
username=elastic
###

# Remove trailing slash from URL if there is any
ESurl="${ESurl%/}"

function promptPassword () {
	echo -n "Enter a password for user [${username}]: "
	read -s password
}

function checkCommandInstalled () {
	if ! command -v "$1" &> /dev/null
	then
	    echo "command [${1}] could not be found, please ensure it is installed and in the PATH"
	    exit
	fi
}

function checkPrerequisites () {
	checkCommandInstalled "curl"
	checkCommandInstalled "jq"
}

function checkESVersion () {
	ESVersion=$(curl -s -k -u "${username}:${password}" "${ESurl}" | jq --raw-output '.version.number')
	if [[ ! "$ESVersion" = 8* ]]; then
		echo "Version of elasticsearch expected from 8.0.0 to 8.5.3 - detected [${ESVersion}], stopping execution"
		exit
	fi
}

function buildListOfDatafeeds () {
	datafeeds=($(curl -k -u "${username}:${password}" "${ESurl}"/_ml/datafeeds/_stats | jq --raw-output '.datafeeds[].datafeed_id'))
}

function fixDataFeed () {
	echo "INFO : starting no operation update to datafeed [${1}]"
	#If datafeed is started, it needs to be stopped before the update, then restarted
	if [[ $(curl -s -k -u "${username}:${password}" "${ESurl}"/_ml/datafeeds/"$1" | jq --raw-output '.datafeeds[0].state') = "started" ]]; then
		echo "Stoping datafeed [${1}] Do not stop script before it gets restarted"
		curl -s -k -u "${username}:${password}" -XPOST "${ESurl}"/_ml/datafeeds/"$1"/_stop
		echo "Updating datafeed [${1}]" https://github.com/elastic/sdh-ml/issues/401
		curl -s -k -u "${username}:${password}" -XPOST "${ESurl}"/_ml/datafeeds/"$1"/_update -d '{}'
		echo "Restarting datafeed [${1}]"
		curl -s -k -u "${username}:${password}" -XPOST "${ESurl}"/_ml/datafeeds/"$1"/_start
	else
		echo "Updating datafeed [${1}]" https://github.com/elastic/sdh-ml/issues/401
		curl -s -k -u "${username}:${password}" -XPOST "${ESurl}"/_ml/datafeeds/"$1"/_update -d '{}'
	fi
    echo
}

function detect500DatafeedResponse () {
	for datafeed in "${datafeeds[@]}"
	do
		response_code=$(curl -k -u "${username}:${password}" -s -o /dev/null -I -w "%{http_code}" "${ESurl}"/_ml/datafeeds/"$datafeed")
		if [[ "$response_code" = 500 ]]; then
			echo "ERROR detected on datafeed [${datafeed}]"
			if [[ "$fixDatafeeds" = true ]]; then
				fixDataFeed "$datafeed"
			else
				dataFeedsToFix=$((dataFeedsToFix+1)) 
			fi
		else
			echo "INFO : datafeed [${datafeed}] can be parsed, status code [${response_code}]"
		fi
	done
    echo
}

function runALL() {
	checkPrerequisites
	promptPassword
	checkESVersion
	buildListOfDatafeeds
	detect500DatafeedResponse
	if [[ ! "$dataFeedsToFix" = true ]]; then
		echo "SUMMARY: detected [${dataFeedsToFix}] to fix, please run script with : "
		echo "   fixDatafeeds=true ./ml_92168_workaround.sh"
	fi
}

runALL
