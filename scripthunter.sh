#!/bin/bash
# scripthunter.sh
# find javascript files for a website
# Usage: # scripthunter.sh https://www.google.de
# (c) @r0bre 2020
# contact: mail [at] r0b.re
#set -euo pipefail

trap ctrl_c INT

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 &&pwd)"
TMPDIR="/tmp/scripthunter"
WLDIR="${DIR}/wordlists"
wordlist="$WLDIR/scripthunter-wordlist.txt"
jsdirwl="$WLDIR/jsdirs-common.txt"
aggr="$WLDIR/aggregated.txt"
mkdir -p $TMPDIR/results

ctrl_c(){
    echo "interrupt detected, doing cleanup and exiting.."
    do_cleanup
    exit 
}
do_cleanup(){
    rm -rf $TMPDIR/*.txt
    rm -rf $TMPDIR/*.json
}
banner(){
echo "               _      __  __             __         "
echo "  ___ ________(_)__  / /_/ /  __ _____  / /____ ____"
echo " (_-</ __/ __/ / _ \/ __/ _ \/ // / _ \/ __/ -_) __/"
echo "/___/\__/_/ /_/ .__/\__/_//_/\_,_/_//_/\__/\__/_/   "
echo "             /_/   "
echo "                             by @r0bre"
}
usage(){
    echo "Usage: ./scripthunter.sh [-s] [Target URL]"
    echo "       -s: Silent output - No banner, no progress, only urls"
}

tnotify(){
    # Follow this to find your token and chatid
    # https://medium.com/@ManHay_Hong/how-to-create-a-telegram-bot-and-send-messages-with-python-4cf314d9fa3e
    message=$1
    token="CHANGEME"
    chatid="CHANGEME"
    curl -s -X POST https://api.telegram.org/bot$token/sendMessage -d chat_id=$chatid -d text="$message" >/dev/null
    echo "$message" | slackcat
    #or
    #echo "$message" | slackcat -u https://hooks.slack.com/services/xxx/xxx/xxx 
}
if [ $# -eq 0 ] || [ "$1" = "-h" ]
  then
    usage
    exit
fi
if [ "$1" = "-s" ] && [ $# -eq 1 ]
then
    echo "Please Provide a URL!"
    usage
    exit
fi

silent=false
if [ "$1" = "-s" ] && [ $# -eq 2 ]
then
    silent=true
    set -- "$2" # $1=$2
fi

if [ "$silent" = "false" ]; then
    banner
fi

target=`echo "$1" | unfurl format "%s://%d%:%P"`
domain=`echo "$1"| unfurl domain`
if [ "$silent" = "false" ]; then
    echo "[*] Running GAU"
fi
echo "$target" | gau | unfurl format "%s://%d%:%P%p" | grep -iE "\.js$" | sort -u > $TMPDIR/gaujs.txt
gaucount="$(wc -l $TMPDIR/gaujs.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"
if [ "$silent" = "false" ]; then
    echo "[+] GAU found $gaucount scripts!"
fi

if [ "$silent" = "false" ]; then
    echo "[*] Running hakrawler"
fi
hakrawler -js -url $target -plain -depth 2 -scope strict -insecure > $TMPDIR/hakrawl1.txt
cat $TMPDIR/hakrawl1.txt| unfurl format "%s://%d%:%P%p" | grep -iE "\.js$" | sort -u > $TMPDIR/hakrawler.txt
hakcount="$(wc -l $TMPDIR/hakrawler.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"
if [ "$silent" = "false" ]; then
    echo "[+] HAKRAWLER found $hakcount scripts!"
fi

cat $TMPDIR/gaujs.txt $TMPDIR/hakrawler.txt | sort -u > $TMPDIR/gauhak.txt
cat $TMPDIR/gauhak.txt | unfurl format "%s://%d%:%P%p" | grep "\.js$" | rev | cut -d "/" -f2- | rev | sort -u > $TMPDIR/jsdirs.txt
touch $TMPDIR/ffuf.txt
jsdircount="$(wc -l $TMPDIR/jsdirs.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"
if [ "$silent" = "false" ]; then
    echo "[*] Found $jsdircount directories containing .js files."
fi
cat $jsdirwl | while read knowndir; do
    echo "$target/$knowndir" >> $TMPDIR/jsdirs.txt
done
cat $TMPDIR/jsdirs.txt | sort -u | while read jsdir; do

    if [ "$silent" = "false" ]; then
        echo "[*] Running FFUF on $jsdir/"
    fi
    # for more thorough, add .min.js,.common.js,.built.js,.chunk.js,.bundled.js,...
    ffuf -w $wordlist -u $jsdir/FUZZ -e .js,.min.js -mc 200,304 -o $TMPDIR/ffuf.json -s -t 100 > /dev/null
    cat $TMPDIR/ffuf.json | jq -r ".results[].url" | grep "\.js" | unfurl format "%s://%d%:%P%p" | grep -iE "\.js$" | sort -u >$TMPDIR/ffuf_tmp.txt
    cat $TMPDIR/ffuf_tmp.txt >> $TMPDIR/ffuf.txt
    ffuftmpcount="$(wc -l $TMPDIR/ffuf_tmp.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"
    if [ "$silent" = "false" ]; then
        echo "[+] FFUF found $ffuftmpcount scripts in $jsdir/ !"
    fi
done
#echo "[*] Running initial LinkFinder"
#python3 /opt/LinkFinder/linkfinder.py -d -i $target -o cli >> linkfinder.txt


cat $TMPDIR/gauhak.txt $TMPDIR/ffuf.txt | grep "\.js" | grep -v "Running against:" |sort -u > $TMPDIR/results/scripts-$domain.txt
linecount="$(wc -l $TMPDIR/results/scripts-$domain.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"
if [ "$silent" = "false" ]; then
    echo "[+] Checking Script Responsiveness of $linecount scripts.."
fi
cat $TMPDIR/results/scripts-$domain.txt | httpx -status-code -silent -no-color | grep -E '\[200\]$' | cut -d " " -f1 | tee -a $TMPDIR/results/scripts-200-$domain.txt
responsivecount="$(wc -l $TMPDIR/results/scripts-200-$domain.txt | sed -e 's/^[[:space:]]*//' | cut -d " " -f 1)"

tnotify "Scripthunter on $target done. $linecount ($responsivecount responsive) script files found"
if [ "$silent" = "false" ]; then
    echo "[+] All Done!"
    echo "[+] Found total of $linecount ($responsivecount responsive) scripts!"
fi

# Save All Seen js filenames to $aggr wordlist, which we can use in the future
cat $TMPDIR/results/scripts-$domain.txt | rev | cut -d "/" -f1 | rev | sort -u >> $aggr

do_cleanup
