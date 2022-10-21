#!/bin/bash

#### SETTINGS TO CHANGE ####
elasticsearchBaseURL="https://localhost:9200"
username="elastic"
settingUsedForAllocation="index.routing.allocation.require.data"
#For next 3 settings : To skip ; use empty string : ""
valueUsedForHot="hot"
valueUsedForWarm="warm"
valueUsedForCold=""

#### DO NOT CHANGE BELOW SETTINGS ####
password="" # leave this empty to get prompted to not expose sensitive information

############################
# https://www.elastic.co/guide/en/elasticsearch/reference/7.17/migrate-index-allocation-filters.html#set-tier-preference
# This is an example after moving to data tiers and having many indices using custom node attributes 
# The script will find indices in hot/warm/cold to remove the customer node attributes and set tier preference
# requires curl,jq,bash and setting the URL, the setting used for attribute-based allocation filters and value used
############################

function log () {
	# parameter 1 is message
	# parameter 2 log level - ERROR will cause script to exit
	echo "[$(date -u)] $2 - $1"
	if [[ "$2" = "ERROR" ]]; then
		exit 4
	fi
}

function checkCommand () {
	if [[ $(command -v "$1" | wc -l) -eq 0 ]]; then
		log "command [${1}] not found, please install and ensure it's configured in the PATH" "ERROR"
	fi
}

function getIndicesWithSetting () {
	# parameter 1 will be the index setting to look for
	# parameter 2 will be the index setting value to look for
	# function will store result in array variable targetIndices
	if [[ ( -z "$1" ) || ( -z "$2") ]]; then
		log "Missing mandatory parameter 1[${1}] or 2[${2}] for getIndicesWithSetting call" "ERROR"
	fi
	listOfIndices=""
	#note this is 7.7.0+ syntax here
	listOfIndices=($(curl -k -s -u "${username}:${password}" "${elasticsearchBaseURL}/_settings?pretty&human&expand_wildcards=all" | jq --raw-output "to_entries[] | select (.value.settings.${1} == \"${2}\") | .key"))
}

function updateIndicesWithSetting () {
	# parameter 1 will be the index setting to set
	# parameter 2 will be the index setting value to set - note double-quote are needed to allow for value null
	# parameter 3 (optional) will be a second index setting to set
	# parameter 4 (optional) will be a second index setting value to set - note double-quote are needed to allow for value null
	if [[ -n "$listOfIndices" ]]; then
		if [[ ( -n "$1" ) && ( -n "$2" ) ]]; then
			jsonPayload="{ \"${1}\" : ${2}"
			if [[ ( -n "$3" ) && ( -n "$4" ) ]]; then
				jsonPayload="${jsonPayload}, \"${3}\" : ${4}"
			fi
			jsonPayload="${jsonPayload} }"
		else
			log "Missing mandatory parameter 1[${1}] or 2[${2}] for updateIndicesWithSetting call" "ERROR"
		fi
		for index in "${listOfIndices[@]}"
		do
			log "processing index [${index}] to put settings [${jsonPayload}]"
			response_code=$(curl -k -s -H 'Content-Type: application/json' -o /dev/null -w "%{http_code}" -u "${username}:${password}" -XPUT "${elasticsearchBaseURL}/${index}/_settings" -d "${jsonPayload}")
			if [[ ! "$response_code" == "200" ]]; then
				log "HTTP response [${response_code}] returned" "ERROR"
			fi
		done
	fi
}

function checkPrerequisites () {
	checkCommand "jq"
	checkCommand "curl"
	checkCommand "wc"
}

function moveIndicesToTierPreference () {
	if [[ -n "$valueUsedForHot" ]]; then
		getIndicesWithSetting "$settingUsedForAllocation" "$valueUsedForHot"
		updateIndicesWithSetting "$settingUsedForAllocation" "null" "index.routing.allocation.include._tier_preference" "\"data_hot\""
	fi
	if [[ -n "$valueUsedForWarm" ]]; then
		getIndicesWithSetting "$settingUsedForAllocation" "$valueUsedForWarm"
		updateIndicesWithSetting "$settingUsedForAllocation" "null" "index.routing.allocation.include._tier_preference" "\"data_warm,data_hot\""
	fi
	if [[ -n "$valueUsedForCold" ]]; then
		getIndicesWithSetting "$settingUsedForAllocation" "$valueUsedForCold"
		updateIndicesWithSetting "$settingUsedForAllocation" "null" "index.routing.allocation.include._tier_preference" "\"data_cold,data_warm,data_hot\""
	fi
}

function verifyESConnectivity () {
	if [[ -z "$password" ]]; then
		echo -n "Enter a password for user [${username}]: "
		read -s password
	fi
	response_code=$(curl -k -s -o /dev/null -I -w "%{http_code}" -u "${username}:${password}" "$elasticsearchBaseURL")
	if [[ ! "$response_code" == "200" ]]; then
		log "Connection to Elasticsearch failed with HTTP response [${response_code}] for user [${username}] and URL [${elasticsearchBaseURL}]" "ERROR"
	fi
}

function run () {
	checkPrerequisites
	verifyESConnectivity
	moveIndicesToTierPreference
}

run