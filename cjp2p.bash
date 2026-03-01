#!/bin/bash -eu
info() {
    :
    echo "$*" >&2
}
debug() {
    [[ ${DEBUG:-} ]] && echo "$*" >&2
    [ . ]
}
trap 'echo $0 failed at $LINENO $BASH_COMMAND ;echo $0 failed at $BASH_COMMAND >&2 ' ERR
export RUST_BACKTRACE=1
export  RUST_LOG=warn
#coproc strace  -s 999 -tt -e t=read,write ./target/release/cjp2p-bash   
coproc ./target/release/cjp2p-bash   
#cd /dev/shm
mkdir -p shared/peers
cd shared
>peers/159.69.54.127:24254
exec 10<&${COPROC[0]}    
exec 11<&${COPROC[1]}
#[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
please_send_peers() {
    src=$(ls peers/ -tr|tail -20|sort -R|tail -1)
    debug "requesting peers from $src"
    message_out="[{\"PleaseSendPeers\":{}}]"
    echo -ne "$src\n${#message_out}\n$message_out"
}
req() {
    [[ $id ]] || return 0
    if [[ ${eof:-0} -gt 0 ]];then
        if ((offset_wanted>=eof));then 
            offset_wanted=0
        fi
    fi
           
    while [[ -s incoming/$id/$offset_wanted ]];do 
        let offset_wanted+=$BLOCK_SIZE
    done
    srcds=("incoming/$id/.peers/" peers/)
    srcd=${srcds[RANDOM%2]}
    [[ ${src:-} ]] || src=$(find "$srcd" -mindepth 1 -printf "%T@\t%f\n" |sort -n|tail -20|sort -R|tail -1|cut -f 2 )
    [[ ${src:-} ]] || src=$(find peers/ -mindepth 1 -printf "%T@\t%f\n" |sort -n|tail -20|sort -R|tail -1|cut -f 2 )
    debug "requesting $id at $offset_wanted from $src window $((offset_wanted - ${offset_in:-0})), complete $blocks_complete of $blocks_wanted , eof $eof"
    always_returned=""
    [[ -s "peers/$src" ]] && always_returned=",{\"AlwaysReturned\":$(<"peers/$src")}"
    message_out="[{\"PleaseSendContent\":{\"id\":\"$id\",\"length\":$BLOCK_SIZE,\"offset\":$offset_wanted}}$always_returned]"
    echo -ne "$src\n${#message_out}\n$message_out"
    debug "$message_out to $src"
    let offset_wanted+=$BLOCK_SIZE
}
id=${1:-}
eof=${2:-}
mkdir -p "incoming/$id" # this starts the transfer
BLOCK_SIZE=$((0xa000))
[[ $id ]] || id=$(ls incoming/|head -1) # currrently does only one file at a time
if [[ $id ]];then
    mkdir -p "incoming/$id/.peers/"
    [[ $eof ]] && echo $eof > incoming/$id/.eof
    [[ -r incoming/$id/.eof ]] && eof=$(<incoming/$id/.eof)
    offset_wanted=0
    blocks_wanted=$(((eof+BLOCK_SIZE-1)/BLOCK_SIZE))
    blocks_complete=$(ls "incoming/$id/" |wc -l)
    req >&11
fi
last_maintenance=0
while [ . ]  ;do
    #vars=($(timeout 1 strace  -s 999 -e t=read,write head -c 33 <&10 ))   || [ . ] #  race where the head can succeede but not exit in time so be killed so timeout reports failure
    vars=($(timeout 1 head -c 33 <&10 ))   || [ . ] #  race where the head can succeede but not exit in time so be killed so timeout reports failure
    if ((last_maintenance<SECONDS));then
        let last_maintenance=SECONDS
        src= please_send_peers 
        please_send_peers 
        req
        src= req
        src= req
        src= req
        src= req
        src= req
        src= req
        src= req
        src= req
    fi >&11
    if [[ ! ${vars[0]:-} ]];then 
        debug "timeout"
        continue
    fi
    #else
    debug "vars: ${#vars[@]} ${vars[@]}"
    src=${vars[0]}
    len=${vars[1]}
    debug got $len from $src 
    head -c $len <&10 |
        jq -c '.[]' | 
        split -l 1
    [[ -e xaa ]] || continue
    always_return=""
    for message_in in x??;do 
    #    jq -C < $message_in
    #    [{"Content":{"base64":"vLTtmB1Ot1dumq1Hscila3uKZF71KU2E3mDH","eof":1073741824,"id":"1024M","offset":204791808}}]
        case "$(jq -r 'keys[0]' <$message_in)" in
            Content) 
                if vars=($(jq -er '.Content|(.offset |tostring) +" " + .id' < $message_in|tr -d /)) &&
                  [ "${vars[0]:-}" ]; then
                    if [[ ! ${eof:-} ]];then
                        eof=$(jq -er '.Content|(.eof |tostring)'  < $message_in|tr -d /) &&
                        blocks_wanted=$(((eof+BLOCK_SIZE-1)/BLOCK_SIZE))
                        echo "$eof" > "incoming/$id/.eof"
                    fi
                    offset_in="${vars[0]}"
                    id_="${vars[1]}"
                    if [[ -d "incoming/$id_" ]];then
                        id=$id_
                        file="incoming/$id/$offset_in"
                        if [[ -s "$file" ]];then
                            debug "duplicate received block  $file"
                        else
                            > "incoming/$id/.peers/$src"
                            jq -er 'select(.Content)|.Content.base64' < $message_in  |
                                base64 -d  > "$file"
                            # it should really check the length here
                            this_block_size=$(wc -c < $file )
                            debug "received $this_block_size of $id $offset_in window $((offset_wanted - $offset_in)) from $src"
                            if ((this_block_size == BLOCK_SIZE))  || (((this_block_size+offset_in)==eof));then
                                let ++blocks_complete
                            else
                                rm $file
                            fi
                        fi
                        if ((blocks_complete==blocks_wanted));then
                            find "incoming/$id/" -mindepth 1 -maxdepth 1 -not -name '.*'  |
                                sort --numeric-sort --key 3 --field-separator / |
                                xargs cat -- > "$id"
                            rm -rf -- "incoming/$id"
                            echo "$id finished"
                            id=$(ls incoming/|head -1)
                            if [[ $id ]];then
                                offset_wanted=0
                                eof=$(<incoming/$id/.eof)
                                blocks_wanted=$(((eof+BLOCK_SIZE-1)/BLOCK_SIZE))
                                blocks_complete=$(ls "incoming/$id/" |wc -l)
                            fi
                        else
                            req >&11
                            (((RANDOM%101)==0)) && req >&11 # increase packets in flight, so its faster than blocksize/rtt
                        fi
                    else
                        id=$(ls incoming/|head -1)
                        [[ $id ]] && blocks_complete=$(ls "incoming/$id/" |wc -l)
                    fi
            #[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
                fi
                ;;
            PleaseSendContent) 
                if vars=($(jq -er '.PleaseSendContent|(.offset |tostring) +" " + .id + " " + (.length|tostring)' < $message_in|tr -d / )) &&
                  [ ${vars[0]:-} ]; then
                    offset="${vars[0]}"
                    id_outbound="${vars[1]}"
                    length="${vars[2]}"
                    debug "received request for $id_outbound $offset ( $((offset>>12)) 4k blocks ) from $src"
                    if [ -d "incoming/$id_outbound" ];then 
                        find "incoming/$id_outbound/" -name "$((offset-(offset%BLOCK_SIZE)))" -size "+$((length-1+(offset%BLOCK_SIZE)))c"  -fprintf /proc/self/fd/2 "probably sending $id_outbound at $offset length $length to $src" -exec tail -c +$((1+(offset%BLOCK_SIZE))) {} \; 2>/dev/null | 
                            head -c "$length"  > raw
                        eof_=$(<"incoming/$id_outbound/.eof")
                        if [[ ! -s raw ]] || (((RANDOM%73)==0));then 
                            message_out=$(find "incoming/$id_outbound/.peers/" -mindepth 1 -printf "%T@ %f\n" |sort -n|tail -200|sort -R|tail -20|
                                        jq -c --null-input --raw-input "[{MaybeTheyHaveSome: { id: \"$id_outbound\", peers: [inputs|split(\" \")[1]]}}]")
                            debug "sending $message_out"
                            echo -ne "$src\n${#message_out}\n$message_out" 
                        fi
                    elif [[ -s "$id_outbound" ]];then 
                        eof_=$(wc -c < "$id_outbound")
                        tail -c +$((offset+1)) "$id_outbound" |
                            head -c "$length"  > raw
                        debug "should be sending $id_outbound at $offset length $length to $src"
                    fi  
                    [[ -s raw ]]  && < raw base64 -w 0 | 
                    jq  -cRj "[{\"Content\":{\"offset\":$offset,\"id\":\"$id_outbound\",\"eof\":$eof_,\"base64\":.}}]" > message_out && 
                    [[ -s message_out ]] && {
                        debug "really sending $id_outbound at $offset length $length to $src"
                        echo -e "$src\n$(wc -c < message_out )" 
                        cat message_out 
                    } 
                    rm -f message_out raw
                fi >&11
                ;;
            PleaseReturnThisMessage) 
                returned_message=$(jq -cer  '.PleaseReturnThisMessage' < $message_in)
                message_out="[{\"ReturnedMessage\":$returned_message}]"
                debug "sending to $src $message_out" 
                echo -ne "$src\n${#message_out}\n$message_out" >&11
                (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
                ;;
            PleaseSendPeers) 
                message_out=$(find peers/ -mtime -10 -type f -printf "%T@ %f\n" |sort -n|tail -200|sort -R|tail -50| 
                    jq -c --null-input --raw-input '[{Peers: { peers: [inputs|split(" ")[1]]}}]')
                debug "sending $message_out"
                echo -ne "$src\n${#message_out}\n$message_out" >&11
                ;;
            Peers) 
                comm -2 -3 <(jq -cer '.Peers.peers[]' < $message_in |tr -d / | sort ) <(ls peers/ ) |
                    tee >(debug $(wc -l) new peers from $src: ) | 
                    (cd peers && xargs --no-run-if-empty touch -d @1 )
                ;;
            PleaseAlwaysReturnThisMessage) 
                always_return=$(jq -cer '.PleaseAlwaysReturnThisMessage' < $message_in |tr -d / )
                ;;
            MaybeTheyHaveSome) 
                id_=$(jq -cer '.MaybeTheyHaveSome.id' < $message_in |tr -d / )
                if [[ -d "incoming/$id_" ]];then
                    jq -cer '.MaybeTheyHaveSome.peers[]' < $message_in |tr -d / |
                    (cd "incoming/$id_/.peers" && xargs --no-run-if-empty touch --no-create -d @1 )
                fi
                ;;
            *)
                (((RANDOM%11)==0)) && please_send_peers >&11
                (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
                echo -n "$src unknown message: ";jq -cC . < $message_in || cat "$message_in"
                ;;
        esac
    done
    [[ $always_return ]] && echo -n "$always_return" > "peers/$src"
    rm -f x??
done
