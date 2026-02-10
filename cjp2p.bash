#!/bin/bash -eu
debug() {
    :
    echo "$*" >&2
}
trap 'echo $0 failed at $LINENO $BASH_COMMAND ;echo $0 failed at $BASH_COMMAND >&2 ' ERR
export RUST_BACKTRACE=1
export  RUST_LOG=warn
coproc strace -e t=read ./target/release/cjp2p-bash   2>strace
#cd /dev/shm
mkdir -p ${0##*/}.dir
cd ${0##*/}.dir
mkdir -p peers
>peers/159.69.54.127:24254
exec 10<&${COPROC[0]}    
exec 11<&${COPROC[1]}
offset_wanted=0
eof=${2:-}
mkdir -p incoming/${1:-} # this starts the transfer
n=0
BLOCK_SIZE=$((0xa000))
#[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
please_send_peers() {
    src=$(ls peers/ -tr|tail -20|sort -R|tail -1)
    debug requesting peers from $src
    message_out="[{\"PleaseSendPeers\":{}}]"
    echo -ne "$src\n${#message_out}\n$message_out"
}
req() {
    ((offset_wanted<eof)) || return 0
    [[ ${src:-} ]] || src=$(find peers/ -mmin -10 -type f -printf "%T@\t%f\n" |sort -n|tail -20|sort -R|tail -1|cut -f 2 )
    debug requesting $offset_wanted from $src window $((offset_wanted - ${offset_in:-0}))
    message_out="[{\"PleaseSendContent\":{\"id\":\"$id\",\"length\":$BLOCK_SIZE,\"offset\":$offset_wanted}}]"
    echo -ne "$src\n${#message_out}\n$message_out"
    let offset_wanted+=$BLOCK_SIZE
    while [[ -s incoming/$id/$offset_wanted ]];do 
        let offset_wanted+=$BLOCK_SIZE
    done
}
id=$(ls incoming/|head -1) # currrently does only one file at a time
while true;do
    if ! vars=($(timeout 1 head -c 33 <&10 ))  ;then # bump
        [[ $id ]] && {
            ((offset_wanted>eof)) && 
            (($(find incoming/$id/ -mindepth 1 |wc -l) < $(((eof+BLOCK_SIZE-1)/BLOCK_SIZE)))) && {  # missing parts
                offset_wanted=0
            }
            ((offset_wanted>eof)) && {  # done
                    mkdir -p complete
                    find incoming/$id/ -mindepth 1|sort -nk3 -t / |xargs cat > complete/$id
                    rm -rf incoming/$id
                    echo $id done
                    id=$(ls incoming/|head -1)
                }
            req >&11
            src= please_send_peers >&11
        }
        continue
    fi
    src=${vars[0]}
    len=${vars[1]}
    > peers/$src
    head -c $len <&10 |
        jq -c '.[]' | 
        split -l 1
    for message_in in x??;do 
    #    jq -C < $message_in
    #    [{"Content":{"base64":"vLTtmB1Ot1dumq1Hscila3uKZF71KU2E3mDH","eof":1073741824,"id":"1024M","offset":204791808}}]
        case "$(jq -r 'keys[0]' <$message_in)" in
            Content) 
                if vars=($(jq -er '.Content|(.offset |tostring) +" " + .id' < $message_in|tr -d /)) &&
                  [ ${vars[1]:-} ]; then
                    offset_in=${vars[0]}
                    id=${vars[1]}
                    debug received $id $offset_in window $((offset_wanted - $offset_in)) from $src
                    file=incoming/$id/$offset_in
                    if [[ -s $file ]];then
                        debug duplicate received block  $file 
                    else
                        jq -er 'select(.Content)|.Content.base64' < $message_in  |
                            base64 -d  > $file 2>/dev/null  || [ . ]  # oddly forkingg here or anywhere doesnt make this go noticably faster. 
                    fi
                    req >&11
                    (((RANDOM%101)==0)) && req >&11 # increase packets in flight, so its faster than blocksize/rtt
            #[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
                fi
                ;;
            PleaseSendContent) 
                if vars=($(jq -er '.PleaseSendContent|(.offset |tostring) +" " + .id + " " + (.length|tostring)' < $message_in|tr -d /))  &&
                  [ ${vars[1]:-} ]; then
                    offset=${vars[0]}
                    id=${vars[1]}
                    length=${vars[2]}
                    debug "received request for $id $offset ( $((offset>>12)) 4k blocks ) from $src"
                    if [[ -s complete/$id ]];then 
                        tail -c +$((offset+1)) complete/$id |head -c $length
                    fi |
                        base64 -w 0 | 
                        jq  -cRjn "[{\"Content\":{\"offset\":$offset,\"id\":\"$id\",\"base64\":input,\"eof\":$(wc -c < complete/$id)}}]" > message_out 2>/dev/null || [ . ]
                    [[ -s message_out ]] && {
                        echo -e "$src\n$(wc -c < message_out )" >&2
                        echo -e "$src\n$(wc -c < message_out )"
                        cat message_out
                    } >&11
                fi
                ;;
            PleaseReturnThisMessage) 
                returned_message=$(jq -cer  '.PleaseReturnThisMessage' < $message_in)
                message_out="[{\"ReturnedMessage\":$returned_message}]"
                debug sending to $src "$message_out" 
                echo -ne "$src\n${#message_out}\n$message_out" >&11
                (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
                ;;
            PleaseSendPeers) 
                message_out=$(find peers/ -mtime -10 -type f -printf "%T@ %f\n" |sort -n|tail -200|sort -R|tail -50| 
                    jq -c --null-input --raw-input '[{Peers: { peers: [inputs|split(" ")[1]]}}]')
                debug sending $message_out
                echo -ne "$src\n${#message_out}\n$message_out" >&11
                ;;
            Peers) 
                comm -2 -3 <(jq -cer '.Peers.peers[]' < $message_in |tr -d / | sort ) <(ls peers/ ) |
                    tee >(debug $(wc -l) new peers from $src: ) | 
                    (cd peers;xargs --no-run-if-empty touch -d @1 )
                ;;
            *)
                (((RANDOM%11)==0)) && please_send_peers >&11
                (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
                echo -n $src unknown message: ;jq -cC . < $message_in || cat "$message_in"
                ;;
        esac
    done
    rm -f x??
done
