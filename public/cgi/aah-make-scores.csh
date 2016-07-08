#!/bin/tcsh
setenv APP "aah"
setenv API "scores"
if ($?TMP == 0) setenv TMP "/tmp"
setenv WWW "http://www.dcmartin.com/CGI/"
setenv LAN "192.168.1"
# don't update statistics more than once per 12 hours
set TTL = `echo "12 * 60 * 60" | bc`
set SECONDS = `date "+%s"`
set DATE = `echo $SECONDS \/ $TTL \* $TTL | bc`

echo ">>> $APP-$API ($0 $$) - BEGIN $DATE" >>! $TMP/LOG

if (-e ~$USER/.cloudant_url) then
    set cc = ( `cat ~$USER/.cloudant_url` )
    if ($#cc > 0) set CU = $cc[1]
    if ($#cc > 1) set CN = $cc[2]
    if ($#cc > 2) set CP = $cc[3]
endif

if ($?CLOUDANT_URL) then
    set CU = $CLOUDANT_URL
else if ($?CN && $?CP) then
    set CU = "$CN":"$CP"@"$CN.cloudant.com"
else
    echo "+++ $APP-$API ($0 $$) -- No Cloudant URL" >>! $TMP/LOG
    exit
endif

if ($?QUERY_STRING) then
    set DB = `echo "$QUERY_STRING" | sed "s/.*db=\([^&]*\).*/\1/"` 
    set class = `echo "$QUERY_STRING" | sed "s/.*id=\([^&]*\)/\1/"`
endif
if ($#DB == 0) set DB = rough-fog
if ($#class == 0) set class = all
setenv QUERY_STRING "db=$DB&id=$class"

# output set
set JSON = "$TMP/$APP-$API-$QUERY_STRING.$DATE.json"
set INPROGRESS = ( `echo "$JSON".*` )

# check JSON in-progress for current interval
if ($#INPROGRESS) then
    echo "+++ $APP-$API ($0 $$) - IN-PROGRESS $INPROGRESS - EXIT" >>! $TMP/LOG
    exit
else
    if ($DB == "damp-cloud") then
        # damp cloud (visual-classifier, score, time) Public Access
        curl -L -s -q -o "$JSON.$$" "https://ibmcds.looker.com/looks/gGt5s3SmqfMt2HDbr7R2pCNcM2th3h4s.json?apply_formatting=true"
    else
        # rough fog (visual-classifier, score, time) Public Access
        curl -L -s -q -o "$JSON.$$" "https://ibmcds.looker.com/looks/9fBDPkqVtjHyBJqQBr6xrW4JP9dXgkRv.json?apply_formatting=true"
    endif

    echo '{"device":"'$DB'", "scores":' >! "$JSON".$$.$$

    if ($DB == "damp-cloud") then
        cat "$JSON".$$ \
            | sed "s/dampcloud\.alchemy_//" \
            | sed "s/dampcloud_visual_scores\.name/name/" \
            | sed 's/"dampcloud_visual_scores\.score":"\([^"]*\)"/"score":\1/g' >> "$JSON".$$.$$
    else
        cat "$JSON".$$ \
            | sed "s/roughfog\.alchemy_//" \
            | sed "s/roughfog_visual_scores\.name/name/" \
            | sed 's/"roughfog_visual_scores\.score":"\([^"]*\)"/"score":\1/g' >> "$JSON".$$.$$
    endif
    rm -f "$JSON.$$"
    echo '}' >> "$JSON.$$.$$"
    mv -f "$JSON".$$.$$ "$JSON"
endif

# update cloudant later
exit

#
# update Cloudant
#
if ($?CLOUDANT_OFF == 0 && $?CU && $?DB) then
    set DEVICE_DB = `curl -s -q -X GET "$CU/$DB-$API" | /usr/local/bin/jq '.db_name'`
    if ( "$DEVICE_DB" == "null" ) then
	# create DB
	set DEVICE_DB = `curl -s -q -X PUT "$CU/$DB-$API" | /usr/local/bin/jq '.ok'`
	# test for success
	if ( "$DEVICE_DB" != "true" ) then
	    # failure
	    setenv CLOUDANT_OFF TRUE
	endif
    endif
    if ( $?CLOUDANT_OFF == 0 ) then
	set doc = ( `curl -s -q "$CU/$DB-$API/$class" | jq ._id,._rev | sed 's/"//g'` )
	if ($#doc == 2 && $doc[1] == $class && $doc[2] != "") then
	    set rev = $doc[2]
	    echo "+++ $APP-$API ($0 $$) -- DELETE $CU/$DB-$API/$class $rev" >>! $TMP/LOG
	    curl -s -q -X DELETE "$CU/$DB-$API/$class?rev=$rev"
	endif
	echo "+++ $APP-$API ($0 $$) -- STORE $CU/$DB-$API/$class" >>! $TMP/LOG
	curl -s -q -H "Content-type: application/json" -X PUT "$CU/$DB-$API/$class" -d "@$JSON" >>! $TMP/LOG
    endif
else
    echo "+++ $APP-$API ($0 $$) -- No CLOUDANT update" >>! $TMP/LOG
endif
