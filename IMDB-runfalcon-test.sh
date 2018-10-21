#!/bin/sh

URL_RUN="http://serv01.runfalcon.com:8083/techandsolve/run"
URL_STATUS="http://serv01.runfalcon.com:8083/techandsolve/status"

TOKEN="$1"
SCENARIO_CODE="$2"

STATUS_SCHEDULED="SCHEDULED"
STATUS_RUNNING="RUNNING"
STATUS_ERROR="ERROR"

if [ -z "$3" ]
then
	HIGH_RANGE=80
else
	HIGH_RANGE=$3
fi;

if [ -z "$4" ]
then
	MEDIUM_RANGE=40
else
	HIGH_RANGE=$4
fi;

COMPLIANCE_VIOLATION=0

JOB_ID=0

log() {
	echo "[$(date)] LOG  : $1"
}

warn() {
	echo "[$(date)] WARN : $1"
}

err() {
	echo "[$(date)] ERROR: $1"
}

graterOrEqualThan() {
	return `echo "$1 >= $2"|bc`
}

evalPerformance() {
	graterOrEqualThan $2 $HIGH_RANGE
	RESULT=$?
	if [ $RESULT -eq 1 ] ; then
		log "$1: MUY BUENO"
	else
		graterOrEqualThan $2 $MEDIUM_RANGE
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			warn "$1: REGULAR"
		else
			warn "$1: MALO"
			COMPLIANCE_VIOLATION=$(($COMPLIANCE_VIOLATION + 1))
		fi;
	fi;
}

runScenario() {
	log "Running scenario $SCENARIO_CODE ..."
	RESPONSE=`curl --header "Authorization: Bearer $TOKEN" -X POST "$URL_RUN/$SCENARIO_CODE"`
	JOB_ID=`echo $RESPONSE | jq '.id'`
}

checkScenarioStatus() {
	STATUS="$STATUS_SCHEDULED"

	log "Checking status of job $1 ..."
	RESPONSE=`curl --header "Authorization: Bearer $TOKEN" -X POST "$URL_STATUS/$1"`
	STATUS=`echo $RESPONSE | jq '.status'`
	log "[1] Status of job $1: $STATUS ..."
	while [ "$STATUS" == "\"$STATUS_SCHEDULED\"" ] || [ "$STATUS" == "\"$STATUS_RUNNING\"" ]; do
		log "Wating for job $1 with status $STATUS ..."
		sleep 15
		RESPONSE=`curl --header "Authorization: Bearer $TOKEN" -X POST "$URL_STATUS/$1"`
		STATUS=`echo $RESPONSE | jq '.status'`
		log "[2] Status of job $1: $STATUS ..."
	done

	if [[ "$STATUS" == "\"$STATUS_ERROR\"" ]]; then
		err "The job $1 ended with status $STATUS_ERROR"
		exit 10
	fi

	#echo ""
	#log "Service Response:"
	#echo $RESPONSE | jq '.'

	LATENCY_COMPLIANCE=`echo $RESPONSE | jq '.performance.latencyAverageMillisecondsCompliance'`
	ERRORS_COMPLIANCE=`echo $RESPONSE | jq '.performance.errorsPercentageCompliance'`
	THROUGPUT_COMPLIANCE=`echo $RESPONSE | jq '.performance.throughputPerMinuteCompliance'`
	DEVIATION_COMPLIANCE=`echo $RESPONSE | jq '.performance.deviationMillisecondsCompliance'`

	log "LATENCY_COMPLIANCE: $LATENCY_COMPLIANCE"
	log "ERRORS_COMPLIANCE: $ERRORS_COMPLIANCE"
	log "THROUGPUT_COMPLIANCE: $THROUGPUT_COMPLIANCE"
	log "DEVIATION_COMPLIANCE: $DEVIATION_COMPLIANCE"

	echo ""
	log "Results:"
	log "--------"

	evalPerformance "LATENCIA" $LATENCY_COMPLIANCE
	evalPerformance "ERRORS" $ERRORS_COMPLIANCE
	evalPerformance "THROUGPUT" $THROUGPUT_COMPLIANCE
	evalPerformance "DEVIATION" $DEVIATION_COMPLIANCE
}

#### MAIN SCRIPT
runScenario
checkScenarioStatus $JOB_ID

echo ""
echo "exit code $COMPLIANCE_VIOLATION"
exit $COMPLIANCE_VIOLATION
